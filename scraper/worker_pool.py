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

        self._task_queue: asyncio.Queue = asyncio.Queue()
        self._workers: list[WorkerState] = []
        self._worker_tasks: list[asyncio.Task] = []
        self._memory_watchdog: Optional[MemoryWatchdog] = None
        self._running = False
        # palette_counter moved to per-worker WorkerState to avoid race condition

    # ------------------------------------------------------------------
    # Lifecycle
    # ------------------------------------------------------------------

    async def start(self):
        """Initialize workers and memory watchdog."""
        if self._running:
            return

        self._memory_watchdog = MemoryWatchdog(on_threshold=self._handle_memory_pressure)
        await self._memory_watchdog.start()

        # Create worker states with channel assignment
        channels = [name for name, cfg in self.proxy_rotator.channels.items() if cfg.enabled]
        for i in range(self.max_workers):
            channel = channels[i % len(channels)] if channels else "direct"
            profile = WORKER_PROFILES[i % len(WORKER_PROFILES)]
            worker = WorkerState(worker_id=i, channel=channel, profile=profile)
            self._workers.append(worker)

        self._running = True
        logger.info(f"[WorkerPool] Started with {self.max_workers} workers")

    async def stop(self):
        """Gracefully stop all workers and watchdog."""
        self._running = False

        # Signal workers to stop by putting None sentinels
        for _ in self._workers:
            await self._task_queue.put(None)

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

        Args:
            batch_id: Rails SourcingBatch ID for checkpoint correlation
            asins_by_channel: dict from ProxyRotator.distribute_asins()
        """
        # Build channel map for checkpoint
        all_asins = []
        channel_map = {}
        for channel, asins in asins_by_channel.items():
            for asin in asins:
                channel_map[asin] = channel
                all_asins.append(asin)

        # Initialize checkpoint
        self.checkpoint.init_batch(batch_id, all_asins, channel_map)

        # Check for already-completed ASINs (resume support)
        remaining = self.checkpoint.get_remaining(batch_id)
        remaining_set = set(remaining)

        # Enqueue only remaining ASINs
        for channel, asins in asins_by_channel.items():
            for asin in asins:
                if asin in remaining_set:
                    await self._task_queue.put((asin, channel, batch_id))

        if not remaining:
            logger.info(f"[WorkerPool] Batch {batch_id}: all ASINs already completed")
            return

        logger.info(
            f"[WorkerPool] Batch {batch_id}: {len(remaining)} ASINs queued "
            f"(of {len(all_asins)} total)"
        )

        # Start worker coroutines
        self._worker_tasks = [
            asyncio.create_task(self._worker_loop(worker))
            for worker in self._workers
        ]

        # Wait for all items to be processed
        await self._task_queue.join()

        # Signal workers to stop
        for _ in self._workers:
            await self._task_queue.put(None)

        await asyncio.gather(*self._worker_tasks, return_exceptions=True)
        self._worker_tasks.clear()

        # Flush remaining results
        await self.result_buffer.flush()

        progress = self.checkpoint.get_progress(batch_id)
        logger.info(f"[WorkerPool] Batch {batch_id} complete: {progress}")

    # ------------------------------------------------------------------
    # Worker loop
    # ------------------------------------------------------------------

    async def _worker_loop(self, worker: WorkerState):
        """Main loop for a single worker."""
        worker.is_running = True

        # Initialize browser session with stealth profile
        if worker.session is None:
            proxy = self.proxy_rotator.get_proxy(worker.channel)
            worker.session = SessionManager()
            # Session start happens on first fetch (lazy init)

        logger.info(
            f"[Worker {worker.worker_id}] Started on channel={worker.channel} "
            f"tz={worker.profile['timezone']}"
        )

        try:
            while True:
                item = await self._task_queue.get()
                if item is None:
                    self._task_queue.task_done()
                    break

                asin, channel, batch_id = item
                await self._scrape_one(worker, asin, channel, batch_id)
                self._task_queue.task_done()

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
                self.checkpoint.mark_failed(batch_id, asin, "blocked_by_amazon")
                logger.warning(f"[Worker {worker.worker_id}] BLOCKED on {asin}")
                return

            # Parse product data
            data = parse_product_page(page, asin=asin)

            # Record success
            self.rate_limiter.record_success(channel)
            self.proxy_rotator.record_success(channel)
            self.checkpoint.mark_completed(batch_id, asin, data)
            await self.result_buffer.add(data)

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
            "queue_size": self._task_queue.qsize(),
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
