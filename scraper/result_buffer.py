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
    ) -> None:
        self.buffer: list[dict] = []
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

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    async def add(self, result: dict) -> None:
        """Append one result; trigger a flush when the buffer is full."""
        async with self._lock:
            self.buffer.append(result)
            if len(self.buffer) >= self.batch_size:
                # Flush inline (still holding the lock so callers wait).
                await self._do_flush()

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
        async with self._lock:
            if self.buffer:
                await self._do_flush()
        logger.info("BatchResultBuffer: stopped. Final stats: %s", self.stats)

    async def flush(self) -> None:
        """Public flush — acquires lock then calls the inner implementation."""
        async with self._lock:
            await self._do_flush()

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
        """Runs as a background task; flushes on each interval tick."""
        while True:
            await asyncio.sleep(self.flush_interval)
            async with self._lock:
                if self.buffer:
                    await self._do_flush()

    async def _do_flush(self) -> None:
        """
        Core flush logic — called while holding ``self._lock``.
        Attempts up to 3 times with exponential backoff; writes a local
        fallback file if all attempts fail.
        """
        if not self.buffer:
            return

        batch = list(self.buffer)
        self._batch_counter += 1
        payload = {"products": batch, "batch_id": self._batch_counter}
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
                        self.rails_endpoint,
                        json=payload,
                        headers=headers,
                    )
                    if response.is_success:
                        success = True
                        logger.info(
                            "BatchResultBuffer: flushed %d items (attempt %d, status %d)",
                            len(batch),
                            attempt,
                            response.status_code,
                        )
                        break
                    else:
                        last_error = f"HTTP {response.status_code}: {response.text[:200]}"
                        logger.warning(
                            "BatchResultBuffer: flush attempt %d failed — %s",
                            attempt,
                            last_error,
                        )
                except Exception as exc:  # noqa: BLE001
                    last_error = str(exc)
                    logger.warning(
                        "BatchResultBuffer: flush attempt %d exception — %s",
                        attempt,
                        last_error,
                    )

                if attempt < len(delays):
                    await asyncio.sleep(delay)

        # Always clear the buffer regardless of outcome.
        self.buffer.clear()

        now_iso = datetime.now(timezone.utc).isoformat()
        if success:
            self._stats["total_sent"] += len(batch)
            self._stats["last_flush_at"] = now_iso
        else:
            self._stats["total_failed"] += len(batch)
            self._stats["last_flush_at"] = now_iso
            await self._write_fallback(batch, now_iso, last_error)

    async def _write_fallback(
        self, batch: list[dict], timestamp: str, reason: Optional[str]
    ) -> None:
        """Persist a failed batch to disk so no data is lost."""
        safe_ts = timestamp.replace(":", "-").replace("+", "Z")
        fallback_dir = os.path.join(os.path.dirname(__file__), "data")
        os.makedirs(fallback_dir, exist_ok=True)
        path = os.path.join(fallback_dir, f"fallback_{safe_ts}.json")
        payload = {
            "timestamp": timestamp,
            "reason": reason,
            "count": len(batch),
            "products": batch,
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
