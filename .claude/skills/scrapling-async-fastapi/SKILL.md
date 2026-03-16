---
name: scrapling-async-fastapi
description: Scrapling AsyncStealthySession + FastAPI integration pattern — SessionManager lifecycle, crash recovery, TTL rotation, lifespan management
version: 1.0.0
triggers:
  - "scrapling.*fastapi"
  - "AsyncStealthySession"
  - "SessionManager"
  - "browser.*session.*fastapi"
---

# Scrapling + FastAPI: AsyncStealthySession Integration

## Pattern: SessionManager with Crash Recovery

```python
from scrapling.fetchers import AsyncStealthySession
import logging, os

class SessionManager:
    """Browser session lifecycle: start → fetch → TTL rotate → crash recover → stop."""

    def __init__(self):
        self.max_pages = int(os.environ.get("BROWSER_MAX_PAGES", "3"))
        self.max_fetches = int(os.environ.get("SESSION_MAX_FETCHES", "100"))
        self._session = None
        self._fetch_count = 0

    async def start(self):
        self._session = AsyncStealthySession(
            headless=True,
            block_webrtc=True,
            hide_canvas=True,
            max_pages=self.max_pages,
            timeout=30000,  # MILLISECONDS, not seconds!
        )
        await self._session.__aenter__()
        self._fetch_count = 0

    async def stop(self):
        if self._session:
            await self._session.__aexit__(None, None, None)
            self._session = None

    async def fetch(self, url: str, **kwargs):
        if not self._session:
            await self.start()
        try:
            page = await self._session.fetch(url, **kwargs)
            self._fetch_count += 1
            if self._fetch_count >= self.max_fetches:
                await self.stop()
                await self.start()
            return page
        except Exception:
            await self.stop()
            await self.start()
            return await self._session.fetch(url, **kwargs)
```

## Pattern: FastAPI Lifespan

```python
from contextlib import asynccontextmanager
from fastapi import FastAPI

@asynccontextmanager
async def lifespan(app: FastAPI):
    manager = SessionManager()
    await manager.start()
    app.state.session = manager
    yield
    await manager.stop()

app = FastAPI(lifespan=lifespan)
```

## Critical Gotchas

1. **Timeout is MILLISECONDS** for browser fetchers (30000 = 30s), not seconds
2. **`.body` returns bytes** since Scrapling v0.4 — decode with `.body.decode('utf-8')` if needed
3. **`max_pages`** controls concurrent tab pool — exceeding it blocks up to 60s then TimeoutError
4. **Do NOT use `disable_resources=True`** for Amazon — creates detectable fingerprint
5. **Mock mode gate**: Check `MOCK_EXTERNAL_APIS` before starting browser session
6. **Sync endpoints (`def`) must become `async def`** when using session — `def` endpoints run in threadpool which can't access the async session

## Fallback Chain

```
1. SessionManager.fetch()              — async, browser reuse (primary)
2. StealthyFetcher.fetch() via         — sync, new browser (fallback)
   asyncio.to_thread()
3. httpx async                         — HTTP only, partial data (last resort)
```

## Health Endpoint Pattern

```python
@app.get("/health")
async def health():
    return {
        "status": "ok",
        "browser_session": app.state.session.stats,
    }
```
