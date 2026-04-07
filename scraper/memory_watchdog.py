import asyncio
import os
from typing import Optional, Callable, Awaitable

import psutil


class MemoryWatchdog:
    def __init__(
        self,
        threshold_mb: int = None,
        interval_seconds: int = 30,
        on_threshold: Optional[Callable[[], Awaitable[None]]] = None,
    ):
        self.threshold_mb = threshold_mb or int(
            os.environ.get("WORKER_MEMORY_LIMIT_MB", 400)
        )
        self.interval_seconds = interval_seconds
        self.on_threshold = on_threshold
        self._task: Optional[asyncio.Task] = None
        self._process = psutil.Process()

    async def start(self):
        self._task = asyncio.create_task(self._monitor_loop())

    async def stop(self):
        if self._task is not None:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
            self._task = None

    def get_current_mb(self) -> float:
        return self._process.memory_info().rss / (1024 * 1024)

    def is_over_threshold(self) -> bool:
        return self.get_current_mb() > self.threshold_mb

    @property
    def stats(self) -> dict:
        current = self.get_current_mb()
        return {
            "current_mb": round(current, 2),
            "threshold_mb": self.threshold_mb,
            "over_threshold": current > self.threshold_mb,
        }

    async def _monitor_loop(self):
        while True:
            await asyncio.sleep(self.interval_seconds)
            if self.is_over_threshold() and self.on_threshold is not None:
                await self.on_threshold()
