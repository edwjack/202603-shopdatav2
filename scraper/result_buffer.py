"""
BatchResultBuffer — accumulates scrape results and pushes them to Rails
in configurable batches with retry/fallback logic.
"""

import asyncio
import json
import logging
import os
from datetime import datetime, timezone
from typing import Optional

import httpx

logger = logging.getLogger(__name__)


class BatchResultBuffer:
    """
    Asyncio-compatible buffer that collects product dicts and flushes them
    to the Rails batch_upsert endpoint in configurable batch sizes or on a
    periodic timer.
    """

    def __init__(
        self,
        batch_size: int = 50,
        flush_interval: float = 30.0,
        rails_endpoint: Optional[str] = None,
        rails_token: Optional[str] = None,
        on_persisted: Optional[callable] = None,
    ) -> None:
        # buffer holds (item_dict, batch_id_or_None, asin_or_None) tuples so
        # we can callback per-item once Rails confirms — needed for the
        # checkpoint scraped→persisted transition (F5 fix).
        self.buffer: list[tuple] = []
        self.batch_size: int = int(os.environ.get("BATCH_RESULT_SIZE", batch_size))
        self.flush_interval: float = float(
            os.environ.get("BATCH_FLUSH_INTERVAL", flush_interval)
        )
        self.rails_endpoint: str = rails_endpoint or os.environ.get(
            "RAILS_BATCH_ENDPOINT",
            "http://localhost:3210/api/products/batch_upsert",
        )
        self.rails_token: str = rails_token or os.environ.get("SCRAPER_API_TOKEN", "")
        self._flush_task: Optional[asyncio.Task] = None
        self._batch_counter: int = 0
        self._stats: dict = {
            "total_sent": 0,
            "total_failed": 0,
            "last_flush_at": None,
        }
        self._lock = asyncio.Lock()
        # Callback invoked with (batch_id, asin) per item once Rails confirms.
        # WorkerPool wires this to checkpoint.mark_persisted.
        self._on_persisted = on_persisted

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    async def add(self, result: dict, batch_id: Optional[int] = None,
                  asin: Optional[str] = None) -> None:
        """Append one result; trigger a flush when the buffer is full.
        batch_id+asin are remembered so on_persisted callback can fire
        per-item after Rails confirms (F5 durability fix)."""
        should_flush = False
        async with self._lock:
            self.buffer.append((result, batch_id, asin))
            if len(self.buffer) >= self.batch_size:
                should_flush = True
        # Flush outside the lock so other workers can keep adding while
        # the HTTP roundtrip (up to ~100s w/ retries) runs (H2/F8 fix).
        if should_flush:
            await self.flush()

    async def start(self) -> None:
        """Start the periodic background flush timer."""
        if self._flush_task is None or self._flush_task.done():
            self._flush_task = asyncio.create_task(self._periodic_flush())
            logger.info(
                "BatchResultBuffer: periodic flush started (interval=%.1fs, batch=%d)",
                self.flush_interval,
                self.batch_size,
            )

    async def stop(self) -> None:
        """Flush any remaining items and cancel the periodic timer."""
        if self._flush_task and not self._flush_task.done():
            self._flush_task.cancel()
            try:
                await self._flush_task
            except asyncio.CancelledError:
                pass
        await self.flush()
        logger.info("BatchResultBuffer: stopped. Final stats: %s", self.stats)

    async def flush(self) -> None:
        """Public flush — swaps buffer under lock, then HTTP I/O outside lock."""
        async with self._lock:
            if not self.buffer:
                return
            batch = self.buffer
            self.buffer = []
            self._batch_counter += 1
            counter = self._batch_counter
        # Lock released. Other workers can now keep adding while we POST.
        await self._post_batch(batch, counter)

    @property
    def stats(self) -> dict:
        return {
            "total_sent": self._stats["total_sent"],
            "total_failed": self._stats["total_failed"],
            "buffer_size": len(self.buffer),
            "last_flush_at": self._stats["last_flush_at"],
        }

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    async def _periodic_flush(self) -> None:
        """Runs as a background task; flushes on each interval tick.
        Wrapped in try/finally so cancellation is clean (H2 fix)."""
        try:
            while True:
                await asyncio.sleep(self.flush_interval)
                try:
                    await self.flush()
                except Exception as exc:  # noqa: BLE001
                    logger.warning("BatchResultBuffer: periodic flush error — %s", exc)
        except asyncio.CancelledError:
            pass

    async def _post_batch(self, batch: list, counter: int) -> None:
        """Send one batch to Rails with retry/backoff. Called outside the
        producer lock so other workers can keep enqueueing during the HTTP
        roundtrip (H2/F8 fix). On success, fires on_persisted per item;
        on failure, writes the fallback file with metadata so the replay
        tool can resend (F5 durability tail)."""
        # batch is list[(item, batch_id, asin)] — extract products only for
        # the wire payload, but keep the metadata for callbacks/fallback.
        products = [tup[0] for tup in batch]
        payload = {"products": products, "batch_id": counter}
        headers = {
            "Authorization": f"Bearer {self.rails_token}",
            "Content-Type": "application/json",
        }

        success = False
        last_error: Optional[str] = None
        delays = [1, 2, 4]

        async with httpx.AsyncClient(http2=True, timeout=30.0) as client:
            for attempt, delay in enumerate(delays, start=1):
                try:
                    response = await client.post(
                        self.rails_endpoint, json=payload, headers=headers,
                    )
                    if response.is_success:
                        success = True
                        logger.info(
                            "BatchResultBuffer: flushed %d items (attempt %d, status %d)",
                            len(batch), attempt, response.status_code,
                        )
                        break
                    last_error = f"HTTP {response.status_code}: {response.text[:200]}"
                    logger.warning(
                        "BatchResultBuffer: flush attempt %d failed — %s",
                        attempt, last_error,
                    )
                except Exception as exc:  # noqa: BLE001
                    last_error = str(exc)
                    logger.warning(
                        "BatchResultBuffer: flush attempt %d exception — %s",
                        attempt, last_error,
                    )
                if attempt < len(delays):
                    await asyncio.sleep(delay)

        now_iso = datetime.now(timezone.utc).isoformat()
        if success:
            self._stats["total_sent"] += len(batch)
            self._stats["last_flush_at"] = now_iso
            # Fire per-item callback so checkpoint can transition to persisted.
            if self._on_persisted:
                for _item, b_id, asin in batch:
                    if b_id is not None and asin:
                        try:
                            self._on_persisted(b_id, asin)
                        except Exception as exc:  # noqa: BLE001
                            logger.warning(
                                "BatchResultBuffer: on_persisted callback failed for "
                                "(batch=%s, asin=%s) — %s", b_id, asin, exc,
                            )
        else:
            self._stats["total_failed"] += len(batch)
            self._stats["last_flush_at"] = now_iso
            # Fallback file gets the metadata-rich form so replay can hit Rails
            # AND mark the checkpoint persisted afterward.
            await self._write_fallback_meta(batch, now_iso, last_error)

    async def _write_fallback_meta(
        self, batch: list[tuple], timestamp: str, reason: Optional[str]
    ) -> None:
        """Persist failed batch with batch_id/asin metadata so the replay tool
        can resend AND mark the checkpoint persisted on success."""
        safe_ts = timestamp.replace(":", "-").replace("+", "Z")
        fallback_dir = os.path.join(os.path.dirname(__file__), "data")
        os.makedirs(fallback_dir, exist_ok=True)
        path = os.path.join(fallback_dir, f"fallback_{safe_ts}.json")
        payload = {
            "timestamp": timestamp,
            "reason": reason,
            "count": len(batch),
            "items": [
                {"batch_id": b_id, "asin": asin, "product": item}
                for item, b_id, asin in batch
            ],
        }
        try:
            with open(path, "w", encoding="utf-8") as fh:
                json.dump(payload, fh, ensure_ascii=False, indent=2)
            logger.error(
                "BatchResultBuffer: %d items written to fallback %s",
                len(batch),
                path,
            )
        except OSError as exc:
            logger.error(
                "BatchResultBuffer: could not write fallback file %s — %s",
                path,
                exc,
            )
