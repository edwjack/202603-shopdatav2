"""Amazon Product Scraper Microservice.

FastAPI service on port 3211 that scrapes Amazon product detail pages
using Scrapling (with fallback to httpx) for full product data collection.

Architecture (v5 — 50K scale):
- 3-channel proxy system (DIRECT / DECODO / SMARTPROXY) with configurable ratio
- WorkerPool with N concurrent browser sessions + stealth profiles
- CheckpointManager for cross-day resume via batch_id correlation
- AdaptiveRateLimiter with per-channel delay adjustment
- BatchResultBuffer pushes results to Rails in batches of 50
- MemoryWatchdog monitors RSS and triggers worker restart
- Runtime config API for hot-reconfiguring proxy ratio and batch sizes
- Legacy /scrape endpoint delegates to /scrape/batch
"""
import os
import json
import time
import uuid
import random
import asyncio
import logging
from contextlib import asynccontextmanager
from typing import Optional

from fastapi import FastAPI, BackgroundTasks, HTTPException
from pydantic import BaseModel

from parsers.images import parse_images
from parsers.overview import parse_overview
from parsers.options import parse_options
from parsers.quantity import parse_quantity
from config import get_proxy, rate_delay, category_pause
from session_manager import SessionManager
from proxy_rotator import ProxyRotator
from rate_limiter import AdaptiveRateLimiter
from checkpoint import CheckpointManager
from result_buffer import BatchResultBuffer
from worker_pool import WorkerPool

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

MOCK_MODE = os.environ.get("MOCK_EXTERNAL_APIS", "true").lower() == "true"

# Per-task state: {task_id: {status, total, completed, failed, results, created_at}}
tasks: dict = {}


# ---------------------------------------------------------------------------
# FastAPI lifespan — manages browser session + worker pool lifecycle
# ---------------------------------------------------------------------------

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Legacy single session (for non-batch endpoints)
    manager = SessionManager()
    if not MOCK_MODE:
        await manager.start()
    app.state.session = manager

    # v5 components
    app.state.proxy_rotator = ProxyRotator()
    app.state.rate_limiter = AdaptiveRateLimiter()
    app.state.checkpoint = CheckpointManager()
    app.state.result_buffer = BatchResultBuffer()
    app.state.worker_pool = WorkerPool(
        proxy_rotator=app.state.proxy_rotator,
        rate_limiter=app.state.rate_limiter,
        checkpoint=app.state.checkpoint,
        result_buffer=app.state.result_buffer,
    )

    if not MOCK_MODE:
        await app.state.worker_pool.start()
        await app.state.result_buffer.start()

    yield

    if not MOCK_MODE:
        await app.state.result_buffer.stop()
        await app.state.worker_pool.stop()
    app.state.checkpoint.close()
    await manager.stop()


app = FastAPI(title="Amazon Scraper", version="5.0.0", lifespan=lifespan)


# ---------------------------------------------------------------------------
# Pydantic request models
# ---------------------------------------------------------------------------

class ScrapeRequest(BaseModel):
    asins: list[str]
    category_id: Optional[int] = None
    batch_id: Optional[int] = None


class BsrRequest(BaseModel):
    amazon_node_id: str
    category_slug: str


class MoversRequest(BaseModel):
    amazon_node_id: str
    category_slug: str


class UrlsRequest(BaseModel):
    amazon_node_id: str
    pages: int = 1


class TrendsRequest(BaseModel):
    keywords: list[str]


class SocialRequest(BaseModel):
    keywords: list[str]
    subreddits: list[str] = []


class ResyncRequest(BaseModel):
    asins: list[str]


# ---------------------------------------------------------------------------
# Task helpers
# ---------------------------------------------------------------------------

def new_task(total: int) -> str:
    """Create a new task entry and return its task_id."""
    task_id = str(uuid.uuid4())
    tasks[task_id] = {
        "status": "in_progress",
        "total": total,
        "completed": 0,
        "failed": 0,
        "results": [],
        "created_at": time.time(),
    }
    return task_id


def cleanup_stale_tasks():
    """Remove tasks older than 1 hour to prevent memory leaks."""
    cutoff = time.time() - 3600
    stale = [tid for tid, t in list(tasks.items()) if t.get("created_at", 0) < cutoff]
    for tid in stale:
        tasks.pop(tid, None)
    if stale:
        logger.info(f"[Cleanup] Removed {len(stale)} stale tasks")


# ---------------------------------------------------------------------------
# Scraping helpers
# ---------------------------------------------------------------------------

async def scrape_with_session(asin: str) -> dict:
    """Scrape a single Amazon product using managed async session (primary)."""
    from parsers.product_page import parse_product_page
    if not hasattr(app.state, "session"):
        raise RuntimeError("SessionManager not initialized")
    url = f"https://www.amazon.com/dp/{asin}"
    page = await app.state.session.fetch(url, network_idle=True)
    return parse_product_page(page, asin=asin)


async def scrape_with_stealthy_fallback(asin: str) -> dict:
    """Fallback 1: StealthyFetcher via asyncio.to_thread (new browser each call)."""
    from parsers.product_page import parse_product_page

    def _sync_fetch():
        from scrapling.fetchers import StealthyFetcher
        url = f"https://www.amazon.com/dp/{asin}"
        proxy = get_proxy()
        return StealthyFetcher.fetch(url, headless=True, proxy=proxy)

    page = await asyncio.to_thread(_sync_fetch)
    return parse_product_page(page, asin=asin)


async def scrape_with_httpx(asin: str) -> dict:
    """Fallback 2: scrape using httpx (last resort, partial data only)."""
    import httpx

    user_agents = [
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    ]

    url = f"https://www.amazon.com/dp/{asin}"
    headers = {
        "User-Agent": random.choice(user_agents),
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.9",
    }

    async with httpx.AsyncClient(http2=True, timeout=30.0) as client:
        resp = await client.get(url, headers=headers, follow_redirects=True)
        resp.raise_for_status()
        html = resp.text

    return {
        "asin": asin,
        "title": "",
        "price": 0.0,
        "brand": "",
        "review_rating": 0.0,
        "review_count": 0,
        "about_this": [],
        "tags": [],
        "category_name": "",
        "images": parse_images(html),
        "overview": parse_overview(html),
        "options": parse_options(html),
        "quantity": parse_quantity(html),
    }


async def process_scrape(task_id: str, asins: list[str], category_id: Optional[int] = None):
    """Background task: scrape multiple ASINs and store results in task dict."""
    results = []
    for asin in asins:
        try:
            delay = rate_delay("amazon")
            await asyncio.sleep(delay)

            try:
                data = await scrape_with_session(asin)
            except Exception as e1:
                logger.warning(f"[Task {task_id}] SessionManager failed for {asin}: {e1}, trying StealthyFetcher")
                try:
                    data = await scrape_with_stealthy_fallback(asin)
                except Exception as e2:
                    logger.warning(f"[Task {task_id}] StealthyFetcher failed for {asin}: {e2}, trying httpx")
                    data = await scrape_with_httpx(asin)

            results.append(data)
            tasks[task_id]["completed"] += 1
        except Exception as e:
            logger.error(f"Failed to scrape {asin}: {e}")
            tasks[task_id]["failed"] += 1

    tasks[task_id]["status"] = "completed"
    tasks[task_id]["results"] = results
    logger.info(
        f"[Task {task_id}] Scraping complete: "
        f"{tasks[task_id]['completed']}/{tasks[task_id]['total']} "
        f"({tasks[task_id]['failed']} failed)"
    )


async def process_url_collection(task_id: str, amazon_node_id: str, pages: int):
    """Background task: collect ASINs from Best Sellers pages."""
    from parsers.bestsellers import parse_bestsellers

    results = []
    for page_num in range(1, pages + 1):
        try:
            bs_url = f"https://www.amazon.com/gp/bestsellers/{amazon_node_id}/?pg={page_num}"
            delay = rate_delay("amazon")
            await asyncio.sleep(delay)

            if not hasattr(app.state, "session"):
                raise RuntimeError("SessionManager not initialized")
            page = await app.state.session.fetch(bs_url, network_idle=True)
            html = page.body.decode('utf-8') if isinstance(page.body, bytes) else page.body
            products = parse_bestsellers(html)
            for p in products:
                results.append({
                    "asin": p["asin"],
                    "source": "best_sellers",
                    "rank": p.get("bsr_rank"),
                })
            tasks[task_id]["completed"] += len(products)
        except Exception as e:
            logger.error(f"[Task {task_id}] URL collection page {page_num} failed: {e}")
            tasks[task_id]["failed"] += 1

    tasks[task_id]["status"] = "completed"
    tasks[task_id]["results"] = results
    logger.info(f"[Task {task_id}] URL collection complete: {len(results)} ASINs")


async def process_price_resync(task_id: str, asins: list[str]):
    """Background task: re-scrape product pages for updated prices."""
    results = []
    for asin in asins:
        try:
            delay = rate_delay("amazon")
            await asyncio.sleep(delay)

            try:
                data = await scrape_with_session(asin)
            except Exception as e1:
                logger.warning(f"[Task {task_id}] SessionManager failed for {asin}: {e1}, trying StealthyFetcher")
                try:
                    data = await scrape_with_stealthy_fallback(asin)
                except Exception as e2:
                    logger.warning(f"[Task {task_id}] StealthyFetcher failed for {asin}: {e2}, trying httpx")
                    data = await scrape_with_httpx(asin)

            results.append({"asin": asin, "price": data.get("price", 0.0), "success": True})
            tasks[task_id]["completed"] += 1
        except Exception as e:
            logger.error(f"[Task {task_id}] Price resync failed for {asin}: {e}")
            results.append({"asin": asin, "price": None, "success": False, "error": str(e)})
            tasks[task_id]["failed"] += 1

    tasks[task_id]["status"] = "completed"
    tasks[task_id]["results"] = results
    logger.info(f"[Task {task_id}] Price resync complete: {tasks[task_id]['completed']}/{tasks[task_id]['total']}")


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@app.post("/scrape")
async def start_scrape(req: ScrapeRequest, background_tasks: BackgroundTasks):
    """Legacy endpoint — delegates to /scrape/batch with single chunk."""
    cleanup_stale_tasks()
    task_id = new_task(len(req.asins))
    background_tasks.add_task(process_scrape, task_id, req.asins, req.category_id)
    return {"task_id": task_id}


# ---------------------------------------------------------------------------
# v5 Batch scraping endpoints (50K scale)
# ---------------------------------------------------------------------------

class BatchScrapeRequest(BaseModel):
    asins: list[str]
    batch_id: int
    daily_limit: int = 5000


class ProxyRatioRequest(BaseModel):
    direct: float = 5
    decodo: float = 2.5
    smart: float = 2.5


class BatchSizeRequest(BaseModel):
    direct: Optional[int] = None
    decodo: Optional[int] = None
    smart: Optional[int] = None


@app.post("/scrape/batch")
async def start_batch_scrape(req: BatchScrapeRequest, background_tasks: BackgroundTasks):
    """Start batch scraping with WorkerPool + 3-channel proxy distribution.

    Returns task_id for polling via /status/{task_id}.
    Uses CheckpointManager for cross-day resume via batch_id.
    """
    cleanup_stale_tasks()

    if MOCK_MODE:
        logger.info(f"[MOCK] /scrape/batch called for batch_id={req.batch_id}, {len(req.asins)} ASINs")
        task_id = new_task(len(req.asins))
        tasks[task_id]["status"] = "completed"
        tasks[task_id]["completed"] = len(req.asins)
        tasks[task_id]["results"] = [{"asin": a, "mock": True} for a in req.asins]
        return {"task_id": task_id, "batch_id": req.batch_id, "mode": "mock"}

    # Distribute ASINs across channels by weight ratio
    rotator = app.state.proxy_rotator
    asins_by_channel = rotator.distribute_asins(req.asins, daily_limit=req.daily_limit)

    total_queued = sum(len(v) for v in asins_by_channel.values())
    task_id = new_task(total_queued)

    async def _run_batch():
        try:
            pool = app.state.worker_pool
            await pool.run_batch(req.batch_id, asins_by_channel)
            progress = app.state.checkpoint.get_progress(req.batch_id)
            tasks[task_id]["completed"] = progress["completed"]
            tasks[task_id]["failed"] = progress["failed"]
            tasks[task_id]["status"] = "completed"
        except Exception as e:
            logger.error(f"[Batch {req.batch_id}] Failed: {e}")
            tasks[task_id]["status"] = "failed"

    background_tasks.add_task(_run_batch)

    channel_dist = {ch: len(asins) for ch, asins in asins_by_channel.items()}
    return {
        "task_id": task_id,
        "batch_id": req.batch_id,
        "total_queued": total_queued,
        "channel_distribution": channel_dist,
    }


@app.get("/checkpoint/{batch_id}/remaining")
async def get_checkpoint_remaining(batch_id: int):
    """Get remaining ASINs for a batch (for cross-day resume)."""
    checkpoint = app.state.checkpoint
    remaining = checkpoint.get_remaining(batch_id)
    progress = checkpoint.get_progress(batch_id)
    return {
        "batch_id": batch_id,
        "remaining_count": len(remaining),
        "remaining_asins": remaining[:100],  # cap response size
        "progress": progress,
    }


@app.put("/config/proxy-ratio")
async def update_proxy_ratio(req: ProxyRatioRequest):
    """Hot-reconfigure proxy channel ratio without restart."""
    ratio_str = f"{req.direct}:{req.decodo}:{req.smart}"
    app.state.proxy_rotator.reconfigure(ratio_str)
    logger.info(f"[Config] Proxy ratio updated to {ratio_str}")
    return {"ratio": ratio_str, "stats": app.state.proxy_rotator.stats}


@app.put("/config/batch-size")
async def update_batch_size(req: BatchSizeRequest):
    """Update per-channel batch sizes."""
    rotator = app.state.proxy_rotator
    updated = {}
    if req.direct is not None:
        rotator.channels["direct"].batch_size = req.direct
        updated["direct"] = req.direct
    if req.decodo is not None:
        rotator.channels["decodo"].batch_size = req.decodo
        updated["decodo"] = req.decodo
    if req.smart is not None:
        rotator.channels["smart"].batch_size = req.smart
        updated["smart"] = req.smart
    logger.info(f"[Config] Batch sizes updated: {updated}")
    return {"updated": updated}


@app.get("/config/proxy-status")
async def get_proxy_status():
    """Get current proxy channel health, ratio, and cost estimate."""
    return {
        "channels": app.state.proxy_rotator.stats,
        "rate_limiter": {
            ch: {
                "delay": app.state.rate_limiter.get_delay(ch),
                "paused": app.state.rate_limiter.should_pause(ch),
            }
            for ch in app.state.proxy_rotator.channels
        },
        "worker_pool": app.state.worker_pool.stats,
        "result_buffer": app.state.result_buffer.stats,
    }


@app.get("/status/{task_id}")
async def get_task_status(task_id: str):
    """Get status of a specific scraping task."""
    if task_id not in tasks:
        raise HTTPException(status_code=404, detail="Task not found")
    return tasks[task_id]


@app.get("/health")
async def health():
    """Health check endpoint. Always responds quickly (<100ms)."""
    session_stats = app.state.session.stats if hasattr(app.state, "session") else {}
    return {
        "status": "ok",
        "service": "amazon-scraper",
        "version": "4.0.0",
        "browser_session": session_stats,
    }


@app.post("/collect/bsr")
async def collect_bsr(req: BsrRequest):
    """Scrape Amazon Best Sellers for a category node. Async with session reuse."""
    cleanup_stale_tasks()
    from parsers.bestsellers import parse_bestsellers, compute_bsr_stats

    if MOCK_MODE:
        logger.info(f"[MOCK] /collect/bsr called for node {req.amazon_node_id}")
        return {"products": [], "stats": {"avg_bsr": None, "total": 0, "avg_price": None,
                                          "avg_reviews": None, "avg_rating": None,
                                          "fba_ratio": None, "price_in_range_pct": None}}

    try:
        url = f"https://www.amazon.com/gp/bestsellers/{req.amazon_node_id}/"
        page = await app.state.session.fetch(url, network_idle=True)
        html = page.body.decode('utf-8') if isinstance(page.body, bytes) else page.body
        products = parse_bestsellers(html)
        stats = compute_bsr_stats(products)
        logger.info(f"[BSR] Collected {len(products)} products for node {req.amazon_node_id}")
        return {"products": products, "stats": stats}
    except Exception as e:
        logger.error(f"[BSR] Failed for node {req.amazon_node_id}: {e}")
        return {"error": str(e), "products": [], "stats": {}}


@app.post("/collect/movers")
async def collect_movers(req: MoversRequest):
    """Scrape Amazon Movers & Shakers for a category node. Async with session reuse."""
    cleanup_stale_tasks()
    from parsers.movers import parse_movers

    if MOCK_MODE:
        logger.info(f"[MOCK] /collect/movers called for node {req.amazon_node_id}")
        return {"movers": []}

    try:
        url = f"https://www.amazon.com/gp/movers-and-shakers/{req.amazon_node_id}/"
        page = await app.state.session.fetch(url, network_idle=True)
        html = page.body.decode('utf-8') if isinstance(page.body, bytes) else page.body
        movers = parse_movers(html)
        logger.info(f"[Movers] Collected {len(movers)} movers for node {req.amazon_node_id}")
        return {"movers": movers}
    except Exception as e:
        logger.error(f"[Movers] Failed for node {req.amazon_node_id}: {e}")
        return {"error": str(e), "movers": []}


@app.post("/collect/urls")
async def collect_urls(req: UrlsRequest, background_tasks: BackgroundTasks):
    """Collect ASINs from Amazon Best Sellers pages. Returns task_id for polling."""
    cleanup_stale_tasks()
    task_id = new_task(req.pages)
    background_tasks.add_task(process_url_collection, task_id, req.amazon_node_id, req.pages)
    return {"task_id": task_id}


@app.post("/collect/trends")
async def collect_trends(req: TrendsRequest):
    """Collect Google Trends data for keywords."""
    cleanup_stale_tasks()
    try:
        from parsers.trends import fetch_trends
        result = fetch_trends(req.keywords)
        return result
    except ImportError:
        logger.warning("[Trends] parsers/trends.py not yet available")
        return {"trends": [], "error": "trends parser not installed"}
    except Exception as e:
        logger.error(f"[Trends] Failed: {e}")
        return {"trends": [], "error": str(e)}


@app.post("/collect/social")
async def collect_social(req: SocialRequest):
    """Collect Reddit signals."""
    cleanup_stale_tasks()
    try:
        from parsers.social import fetch_social
        result = fetch_social(req.keywords, req.subreddits)
        return result
    except ImportError:
        logger.warning("[Social] parsers/social.py not yet available")
        return {"reddit": {"mentions": 0, "sentiment": None, "top_posts": []}, "tiktok_views": "n/a"}
    except Exception as e:
        logger.error(f"[Social] Failed: {e}")
        return {"reddit": {"mentions": 0, "sentiment": None, "top_posts": []}, "tiktok_views": "n/a", "error": str(e)}


@app.post("/resync/price")
async def resync_price(req: ResyncRequest, background_tasks: BackgroundTasks):
    """Re-scrape product pages for updated prices. Returns task_id for polling."""
    cleanup_stale_tasks()
    task_id = new_task(len(req.asins))
    background_tasks.add_task(process_price_resync, task_id, req.asins)
    return {"task_id": task_id}


if __name__ == "__main__":
    import uvicorn

    port = int(os.environ.get("SCRAPER_PORT", "3211"))
    uvicorn.run(app, host="127.0.0.1", port=port)
