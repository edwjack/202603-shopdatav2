"""Browser session lifecycle manager with crash recovery and TTL rotation."""
import logging
import os

logger = logging.getLogger(__name__)


class SessionManager:
    """Manages AsyncStealthySession with auto-recovery and TTL rotation."""

    def __init__(self):
        self.max_pages = int(os.environ.get("BROWSER_MAX_PAGES", "3"))
        self.max_fetches = int(os.environ.get("SESSION_MAX_FETCHES", "100"))
        self._session = None
        self._fetch_count = 0

    async def start(self):
        """Create and enter async session."""
        from scrapling.fetchers import AsyncStealthySession
        self._session = AsyncStealthySession(
            headless=True,
            block_webrtc=True,
            hide_canvas=True,
            max_pages=self.max_pages,
            timeout=30000,  # milliseconds
        )
        await self._session.__aenter__()
        self._fetch_count = 0
        logger.info(f"[SessionManager] Started (max_pages={self.max_pages})")

    async def stop(self):
        """Close session gracefully."""
        if self._session:
            try:
                await self._session.__aexit__(None, None, None)
            except Exception as e:
                logger.warning(f"[SessionManager] Close error: {e}")
            self._session = None
            logger.info("[SessionManager] Stopped")

    async def fetch(self, url: str, **kwargs) -> object:
        """Fetch with crash recovery and TTL rotation."""
        if self._session is None:
            await self.start()

        try:
            page = await self._session.fetch(url, **kwargs)
            self._fetch_count += 1

            # TTL: recreate after max_fetches (fingerprint refresh)
            if self._fetch_count >= self.max_fetches:
                logger.info(f"[SessionManager] TTL reached ({self.max_fetches}), rotating")
                await self.stop()
                await self.start()

            return page
        except Exception as e:
            logger.warning(f"[SessionManager] Fetch failed: {e}, recreating session")
            await self.stop()
            await self.start()
            return await self._session.fetch(url, **kwargs)

    @property
    def is_active(self) -> bool:
        return self._session is not None

    @property
    def stats(self) -> dict:
        return {
            "active": self.is_active,
            "fetch_count": self._fetch_count,
            "max_pages": self.max_pages,
            "max_fetches": self.max_fetches,
        }
