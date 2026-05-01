"""WorkerPool — manages N concurrent browser workers with channel-based proxy assignment.

Architecture:
  WorkerPool
  ├── Worker 0: SessionManager + DIRECT channel + BrowserProfile_0
  ├── Worker 1: SessionManager + DECODO channel + BrowserProfile_1
  └── Worker 2: SessionManager + SMARTPROXY channel + BrowserProfile_2

Each worker:
  1. Pulls (asin, channel) from task_queue
  2. Fetches with stealth profile (viewport/locale/timezone/UA)
  3. Parses product data → pushes to result_queue
  4. Adaptive delay from RateLimiter
  5. TTL rotation every 100 fetches
  6. Human-like behavior: referrer chain, palette cleanse
"""
import os
import asyncio
import logging
import random
from dataclasses import dataclass, field
from typing import Optional, Callable, Awaitable

from session_manager import SessionManager
from proxy_rotator import ProxyRotator
from rate_limiter import AdaptiveRateLimiter
from checkpoint import CheckpointManager
from result_buffer import BatchResultBuffer
from memory_watchdog import MemoryWatchdog

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Stealth browser profiles — each worker looks like a different US user
# ---------------------------------------------------------------------------

WORKER_PROFILES = [
    {
        "viewport": {"width": 1920, "height": 1080},
        "locale": "en-US",
        "timezone": "America/New_York",
        "user_agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        ),
    },
    {
        "viewport": {"width": 1440, "height": 900},
        "locale": "en-US",
        "timezone": "America/Chicago",
        "user_agent": (
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36"
        ),
    },
    {
        "viewport": {"width": 1366, "height": 768},
        "locale": "en-US",
        "timezone": "America/Los_Angeles",
        "user_agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36"
        ),
    },
    {
        "viewport": {"width": 1536, "height": 864},
        "locale": "en-US",
        "timezone": "America/Denver",
        "user_agent": (
            "Mozilla/5.0 (X11; Linux x86_64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        ),
    },
    {
        "viewport": {"width": 1680, "height": 1050},
        "locale": "en-US",
        "timezone": "America/Phoenix",
        "user_agent": (
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        ),
    },
]

# Palette cleanse URLs — visit between product scrapes to look human
_PALETTE_URLS = [
    "https://www.amazon.com/",
    "https://www.amazon.com/gp/bestsellers/",
    "https://www.amazon.com/gp/new-releases/",
]


@dataclass
class WorkerState:
    """Runtime state for one worker."""
    worker_id: int
    channel: str
    profile: dict
    session: SessionManager = field(default=None, repr=False)
    fetch_count: int = 0
    products_scraped: int = 0
    is_running: bool = False
    palette_counter: int = 0  # per-worker to avoid race condition


class WorkerPool:
    """Manages N concurrent scraping workers with channel assignment.

    Usage:
        pool = WorkerPool(proxy_rotator, rate_limiter, checkpoint, result_buffer)
        await pool.start()
        await pool.run_batch(batch_id, asins_by_channel)
        await pool.stop()
    """

    def __init__(
        self,
        proxy_rotator: ProxyRotator,
        rate_limiter: AdaptiveRateLimiter,
        checkpoint: CheckpointManager,
        result_buffer: BatchResultBuffer,
        max_workers: int = None,
    ):
        self.proxy_rotator = proxy_rotator
        self.rate_limiter = rate_limiter
        self.checkpoint = checkpoint
        self.result_buffer = result_buffer
        self.max_workers = max_workers or int(os.environ.get("SCRAPER_WORKERS", "3"))

        # Per-channel queues (F2 fix). Workers pop from their own channel's
        # queue only — guarantees the proxy/profile actually used matches the
        # task's recorded channel. With a single shared queue, a direct worker
        # could pop a decodo task and stats would lie.
        self._queues: dict[str, asyncio.Queue] = {}
        self._workers: list[WorkerState] = []
        self._worker_tasks: list[asyncio.Task] = []
        self._memory_watchdog: Optional[MemoryWatchdog] = None
        self._running = False
        # Serialize concurrent run_batch calls (F4 fix). Without this, two
        # /scrape/batch hits would share queues and overwrite _worker_tasks.
        self._batch_lock = asyncio.Lock()
        # Guards _handle_ban so multiple workers blocking simultaneously
        # don't try to drain/redistribute the same channel concurrently.
        self._ban_lock = asyncio.Lock()
        # palette_counter moved to per-worker WorkerState to avoid race condition

    # ------------------------------------------------------------------
    # Lifecycle
    # ------------------------------------------------------------------

    async def start(self):
        """Initialize workers, per-channel queues, and memory watchdog."""
        if self._running:
            return

        self._memory_watchdog = MemoryWatchdog(on_threshold=self._handle_memory_pressure)
        await self._memory_watchdog.start()

        # Per-channel queue for every channel known to the rotator (so a
        # banned channel can still receive redistributed work later if it
        # cools down — though current design redistributes once at ban).
        for ch in self.proxy_rotator.channels:
            self._queues[ch] = asyncio.Queue()

        # Create worker states with channel assignment
        channels = [name for name, cfg in self.proxy_rotator.channels.items() if cfg.enabled]
        for i in range(self.max_workers):
            channel = channels[i % len(channels)] if channels else "direct"
            profile = WORKER_PROFILES[i % len(WORKER_PROFILES)]
            worker = WorkerState(worker_id=i, channel=channel, profile=profile)
            self._workers.append(worker)

        self._running = True
        logger.info(
            f"[WorkerPool] Started with {self.max_workers} workers, "
            f"{len(self._queues)} per-channel queues"
        )

    async def stop(self):
        """Gracefully stop all workers and watchdog."""
        self._running = False

        # One sentinel per worker on its own channel queue.
        for worker in self._workers:
            queue = self._queues.get(worker.channel)
            if queue is not None:
                await queue.put(None)

        # Wait for worker tasks to finish
        if self._worker_tasks:
            await asyncio.gather(*self._worker_tasks, return_exceptions=True)
            self._worker_tasks.clear()

        # Stop sessions
        for worker in self._workers:
            if worker.session:
                await worker.session.stop()

        # Stop watchdog
        if self._memory_watchdog:
            await self._memory_watchdog.stop()

        logger.info(f"[WorkerPool] Stopped. Stats: {self.stats}")

    # ------------------------------------------------------------------
    # Batch execution
    # ------------------------------------------------------------------

    async def run_batch(self, batch_id: int, asins_by_channel: dict[str, list[str]]):
        """Run a scraping batch distributing ASINs across channels.

        Serialized via _batch_lock (F4 fix): two concurrent /scrape/batch
        calls cannot share queues / worker_tasks. The second waits for the
        first to release. At 5K/day target this is fine; if true parallel
        batches are ever needed, switch to per-batch worker subsets.

        Wrapped in try/finally so terminal batch status is always persisted
        (F7 fix Gate-2). Without this, an exception inside the queue/join
        path would leave batches.status='in_progress' forever.

        Args:
            batch_id: Rails SourcingBatch ID for checkpoint correlation
            asins_by_channel: dict from ProxyRotator.distribute_asins()
        """
        async with self._batch_lock:
            await self._run_batch_locked(batch_id, asins_by_channel)

    async def _run_batch_locked(self, batch_id: int, asins_by_channel: dict[str, list[str]]):
        # Build channel map for checkpoint
        all_asins = []
        channel_map = {}
        for channel, asins in asins_by_channel.items():
            for asin in asins:
                channel_map[asin] = channel
                all_asins.append(asin)

        # Initialize checkpoint
        self.checkpoint.init_batch(batch_id, all_asins, channel_map)

        terminal = "failed"
        try:
            # Check for already-completed ASINs (resume support)
            remaining = self.checkpoint.get_remaining(batch_id)
            remaining_set = set(remaining)

            # Enqueue only remaining ASINs onto each channel's own queue.
            queued_per_channel: dict[str, int] = {}
            for channel, asins in asins_by_channel.items():
                queue = self._queues.get(channel)
                if queue is None:
                    # Channel was disabled or unknown — fall back to first
                    # enabled queue so work isn't dropped silently. Warn
                    # because the user's channel intent (cost / proxy choice)
                    # is being silently changed.
                    fallback = next(iter(self._queues), None)
                    if fallback is None:
                        logger.error(f"[WorkerPool] No queues available for channel {channel}")
                        continue
                    logger.warning(
                        f"[WorkerPool] Channel {channel!r} has no queue; rerouting "
                        f"{len(asins)} ASINs to {fallback!r}. Stats will record "
                        f"{fallback!r}, not {channel!r}, so proxy intent is preserved "
                        f"in the data path."
                    )
                    queue = self._queues[fallback]
                    channel_for_record = fallback
                else:
                    channel_for_record = channel
                for asin in asins:
                    if asin in remaining_set:
                        await queue.put((asin, channel_for_record, batch_id))
                        queued_per_channel[channel_for_record] = queued_per_channel.get(channel_for_record, 0) + 1

            if not remaining:
                logger.info(f"[WorkerPool] Batch {batch_id}: all ASINs already completed")
                terminal = "completed"
                return

            logger.info(
                f"[WorkerPool] Batch {batch_id}: {len(remaining)} ASINs queued, "
                f"per-channel={queued_per_channel}"
            )

            # Start worker coroutines (one per worker, each pinned to its channel queue)
            self._worker_tasks = [
                asyncio.create_task(self._worker_loop(worker))
                for worker in self._workers
            ]

            # Wait for every channel queue to drain
            await asyncio.gather(*(q.join() for q in self._queues.values()))

            # One sentinel per worker on its own channel queue
            for worker in self._workers:
                q = self._queues.get(worker.channel)
                if q is not None:
                    await q.put(None)

            await asyncio.gather(*self._worker_tasks, return_exceptions=True)
            self._worker_tasks.clear()

            # Flush remaining results
            await self.result_buffer.flush()

            progress = self.checkpoint.get_progress(batch_id)
            terminal = "completed" if progress.get("remaining", 0) == 0 else "failed"
            logger.info(f"[WorkerPool] Batch {batch_id} {terminal}: {progress}")
        finally:
            try:
                self.checkpoint.set_batch_status(batch_id, terminal)
            except Exception as e:
                logger.warning(f"[WorkerPool] set_batch_status failed: {e}")

    # ------------------------------------------------------------------
    # Worker loop
    # ------------------------------------------------------------------

    async def _worker_loop(self, worker: WorkerState):
        """Main loop for a single worker — pulls only from its channel's queue."""
        worker.is_running = True

        # Initialize browser session with channel proxy + stealth profile.
        # Without this, every worker silently falls back to DIRECT and the
        # 3-channel architecture is purely cosmetic (bug C1/F1 from
        # 2026-05-01 5-skill audit).
        if worker.session is None:
            proxy = self.proxy_rotator.get_proxy(worker.channel)
            worker.session = SessionManager(proxy=proxy, profile=worker.profile)
            # Session start happens on first fetch (lazy init)

        my_queue = self._queues.get(worker.channel)
        if my_queue is None:
            logger.error(
                f"[Worker {worker.worker_id}] No queue for channel {worker.channel}"
            )
            worker.is_running = False
            return

        logger.info(
            f"[Worker {worker.worker_id}] Started on channel={worker.channel} "
            f"tz={worker.profile['timezone']}"
        )

        try:
            while True:
                item = await my_queue.get()
                if item is None:
                    my_queue.task_done()
                    break

                asin, channel, batch_id = item
                # By construction channel == worker.channel (per-channel queue),
                # but we still pass it through to keep stats correct if a future
                # redistribute hands us cross-channel work.
                await self._scrape_one(worker, asin, channel, batch_id)
                my_queue.task_done()

        except asyncio.CancelledError:
            pass
        except Exception as e:
            logger.error(f"[Worker {worker.worker_id}] Fatal error: {e}")
        finally:
            worker.is_running = False

    async def _scrape_one(self, worker: WorkerState, asin: str, channel: str, batch_id: int):
        """Scrape a single ASIN with stealth behavior."""
        from parsers.product_page import parse_product_page

        # Check if channel should pause (3+ consecutive blocks)
        if self.rate_limiter.should_pause(channel):
            logger.warning(f"[Worker {worker.worker_id}] Channel {channel} paused (3+ blocks)")
            await asyncio.sleep(300)  # 5 min pause
            self.rate_limiter.reset(channel)

        # Adaptive delay before request
        delay = self.rate_limiter.get_delay(channel)
        await asyncio.sleep(delay)

        # Palette cleanse: visit a non-product page every 10-20 products
        worker.palette_counter += 1
        if worker.palette_counter >= random.randint(10, 20):
            worker.palette_counter = 0
            await self._palette_cleanse(worker)

        # Validate ASIN format to prevent URL injection
        import re
        if not re.fullmatch(r'[A-Z0-9]{10}', asin):
            self.checkpoint.mark_failed(batch_id, asin, f"invalid_asin_format: {asin[:20]}")
            logger.warning(f"[Worker {worker.worker_id}] Invalid ASIN format: {asin[:20]}")
            return

        url = f"https://www.amazon.com/dp/{asin}"

        try:
            # Ensure session is started
            if not worker.session.is_active:
                await worker.session.start()

            page = await worker.session.fetch(url, network_idle=True)

            # Check for CAPTCHA/block
            html = page.body if hasattr(page, 'body') else str(page)
            if isinstance(html, bytes):
                html = html.decode('utf-8', errors='replace')

            if self._is_blocked(html):
                self.rate_limiter.record_failure(channel, is_ban=True)
                self.proxy_rotator.record_failure(channel, is_ban=True)
                logger.warning(f"[Worker {worker.worker_id}] BLOCKED on {asin}")
                # F3 fix: drain the banned channel's queue and redistribute
                # remaining ASINs to healthy channels. Also requeue THIS
                # blocked ASIN on a healthy channel so it isn't prematurely
                # marked failed — the block was a channel-level signal, not
                # a per-ASIN failure (Gate-2 fix).
                requeued = await self._handle_ban(channel, batch_id, blocked_asin=asin)
                if not requeued:
                    # No healthy channel available — this asin counts as a
                    # retryable failure (mark_failed increments attempts; if
                    # it hits MAX_ATTEMPTS the row goes terminal 'failed').
                    self.checkpoint.mark_failed(batch_id, asin, "blocked_by_amazon")
                return

            # Parse product data
            data = parse_product_page(page, asin=asin)

            # Record success
            self.rate_limiter.record_success(channel)
            self.proxy_rotator.record_success(channel)
            # Two-phase: scraped now (durable in SQLite), persisted only after
            # Rails confirms the batch (callback in result_buffer). Without
            # this, a Rails outage would leave fallback files on disk while
            # SQLite said completed → resume skipped them (F5 bug).
            self.checkpoint.mark_scraped(batch_id, asin, data)
            await self.result_buffer.add(data, batch_id=batch_id, asin=asin)

            worker.products_scraped += 1
            worker.fetch_count += 1

            # TTL rotation every 100 fetches
            if worker.fetch_count >= 100:
                logger.info(f"[Worker {worker.worker_id}] TTL rotation at {worker.fetch_count} fetches")
                await worker.session.stop()
                await worker.session.start()
                worker.fetch_count = 0

        except Exception as e:
            self.rate_limiter.record_failure(channel, is_ban=False)
            self.proxy_rotator.record_failure(channel, is_ban=False)
            self.checkpoint.mark_failed(batch_id, asin, str(e))
            logger.error(f"[Worker {worker.worker_id}] Failed {asin}: {e}")

    # ------------------------------------------------------------------
    # Stealth helpers
    # ------------------------------------------------------------------

    def _is_blocked(self, html: str) -> bool:
        """Detect Amazon CAPTCHA, robot check, or 503 pages."""
        block_signals = [
            "api-services-support@amazon.com",
            "Type the characters you see in this image",
            "Sorry, we just need to make sure you're not a robot",
            "To discuss automated access to Amazon data",
            "automated access to Amazon",
        ]
        html_lower = html.lower()
        return any(signal.lower() in html_lower for signal in block_signals)

    async def _handle_ban(self, banned_channel: str, batch_id: int,
                          blocked_asin: Optional[str] = None) -> bool:
        """Drain remaining items from banned_channel's queue + the in-flight
        blocked ASIN, re-enqueue on healthy channels (F3 fix).

        Returns True if the blocked_asin (if any) was successfully requeued,
        False otherwise. The caller uses this to decide whether to also
        mark_failed the in-flight ASIN.

        Idempotent: guarded by _ban_lock so multiple workers detecting blocks
        in parallel don't drain/redistribute concurrently.
        """
        async with self._ban_lock:
            healthy = [
                ch for ch, cfg in self.proxy_rotator.channels.items()
                if cfg.enabled and not self.proxy_rotator.is_banned(ch) and ch != banned_channel
            ]
            if not healthy:
                logger.warning(
                    f"[WorkerPool] Ban on {banned_channel} but no healthy channel "
                    f"to redistribute to — items stay queued until cooldown ends"
                )
                return False

            banned_queue = self._queues.get(banned_channel)
            drained: list[tuple] = []
            sentinels = 0
            if banned_queue is not None:
                # Non-blocking drain. In-flight tasks already with other
                # workers continue (and will detect the ban themselves).
                while True:
                    try:
                        item = banned_queue.get_nowait()
                    except asyncio.QueueEmpty:
                        break
                    if item is None:
                        sentinels += 1
                        banned_queue.task_done()
                        continue
                    drained.append(item)
                    banned_queue.task_done()
                for _ in range(sentinels):
                    await banned_queue.put(None)

            # Track the in-flight blocked item by position so we don't
            # mis-identify a duplicate queued ASIN as "the one in flight"
            # (Gate-2v2 fix). We always insert it at index 0; the loop
            # below sets blocked_requeued only when index 0 actually
            # lands on a healthy queue.
            blocked_idx: Optional[int] = None
            if blocked_asin:
                drained.insert(0, (blocked_asin, banned_channel, batch_id))
                blocked_idx = 0

            if not drained:
                return False

            logger.warning(
                f"[WorkerPool] Redistributing {len(drained)} ASINs from {banned_channel} "
                f"across {healthy} (incl. in-flight {blocked_asin})"
            )

            # Round-robin across healthy channels, weighted by channel.weight
            total_w = sum(self.proxy_rotator.channels[h].weight for h in healthy)
            healthy_idx = 0
            healthy_cycle: list[str] = []
            for h in healthy:
                w = self.proxy_rotator.channels[h].weight
                count = max(1, round(len(drained) * (w / total_w))) if total_w > 0 else len(drained) // len(healthy)
                healthy_cycle.extend([h] * count)
            while len(healthy_cycle) < len(drained):
                healthy_cycle.append(healthy[healthy_idx % len(healthy)])
                healthy_idx += 1
            healthy_cycle = healthy_cycle[:len(drained)]

            blocked_requeued = False
            for i, ((asin, _old_channel, b_id), new_channel) in enumerate(zip(drained, healthy_cycle)):
                target = self._queues.get(new_channel)
                if target is None:
                    # Healthy channel had no queue (shouldn't happen — start()
                    # populates _queues for every rotator channel — but if it
                    # does, fall back to any other healthy channel).
                    fallback_target = next(
                        (self._queues[h] for h in healthy if h in self._queues and h != new_channel),
                        None,
                    )
                    if fallback_target is None:
                        # Truly nowhere to put it — skip. blocked_requeued stays False.
                        continue
                    target = fallback_target
                await target.put((asin, new_channel, b_id))
                if i == blocked_idx:
                    blocked_requeued = True
            return blocked_requeued

    async def _palette_cleanse(self, worker: WorkerState):
        """Visit a non-product page to look like normal browsing."""
        if not worker.session or not worker.session.is_active:
            return
        try:
            url = random.choice(_PALETTE_URLS)
            await worker.session.fetch(url, network_idle=True)
            await asyncio.sleep(random.uniform(1, 3))
            logger.debug(f"[Worker {worker.worker_id}] Palette cleanse: {url}")
        except Exception:
            pass  # non-critical

    async def _handle_memory_pressure(self):
        """Called by MemoryWatchdog when RSS exceeds threshold."""
        logger.warning("[WorkerPool] Memory pressure detected, restarting workers")
        for worker in self._workers:
            if worker.session and worker.session.is_active:
                await worker.session.stop()
                await worker.session.start()
                worker.fetch_count = 0

    # ------------------------------------------------------------------
    # Stats
    # ------------------------------------------------------------------

    @property
    def stats(self) -> dict:
        return {
            "max_workers": self.max_workers,
            "active_workers": sum(1 for w in self._workers if w.is_running),
            "queue_size": sum(q.qsize() for q in self._queues.values()),
            "queues_per_channel": {ch: q.qsize() for ch, q in self._queues.items()},
            "workers": [
                {
                    "id": w.worker_id,
                    "channel": w.channel,
                    "products_scraped": w.products_scraped,
                    "fetch_count": w.fetch_count,
                    "is_running": w.is_running,
                    "timezone": w.profile["timezone"],
                }
                for w in self._workers
            ],
            "memory": self._memory_watchdog.stats if self._memory_watchdog else {},
        }
