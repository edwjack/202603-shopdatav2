"""Browser session lifecycle manager with crash recovery and TTL rotation."""
import logging
import os

logger = logging.getLogger(__name__)

# US zip code for Amazon delivery location (avoids non-US redirects)
US_ZIP_CODE = os.environ.get("AMAZON_ZIP_CODE", "90006")  # Los Angeles


class SessionManager:
    """Manages AsyncStealthySession with auto-recovery and TTL rotation."""

    def __init__(self):
        self.max_pages = int(os.environ.get("BROWSER_MAX_PAGES", "3"))
        self.max_fetches = int(os.environ.get("SESSION_MAX_FETCHES", "100"))
        self._session = None
        self._fetch_count = 0
        self._location_set = False

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
        self._location_set = False
        logger.info(f"[SessionManager] Started (max_pages={self.max_pages})")

        # Set US delivery location to prevent non-US redirects
        await self._set_us_location()

    async def _set_us_location(self):
        """Warm up session and detect geo-redirect status.

        Amazon uses IP-based geo-redirect. Servers outside the US get
        redirected to regional stores (amazon.sg, amazon.co.jp, etc.).
        This is a server-side 302 that cannot be prevented by cookies,
        headers, or JS — only a US-based proxy resolves it.

        This method:
        1. Visits amazon.com to warm up the browser session
        2. Detects if geo-redirect occurred
        3. Logs the redirect status for monitoring
        """
        try:
            page = await self._session.fetch(
                "https://www.amazon.com/", network_idle=True
            )
            final_url = str(getattr(page, 'url', ''))

            if 'amazon.com' in final_url and '.amazon.co.' not in final_url and '.amazon.sg' not in final_url:
                self._location_set = True
                logger.info(f"[SessionManager] Amazon.com confirmed (no geo-redirect)")
            else:
                # Geo-redirected — log but continue (data is still usable)
                self._location_set = False
                redirected_to = final_url.split('/')[2] if '/' in final_url else final_url
                logger.warning(
                    f"[SessionManager] Geo-redirected to {redirected_to}. "
                    f"Products will be scraped but prices may be in local currency. "
                    f"Use a US proxy (DECODO_PROXY_URL/SMARTPROXY_URL) to fix."
                )
        except Exception as e:
            logger.warning(f"[SessionManager] Session warmup failed: {e}")

    @property
    def is_us_location(self) -> bool:
        """Whether the session is confirmed on amazon.com (not geo-redirected)."""
        return self._location_set

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
