"""Amazon Product Scraper Microservice.

FastAPI service on port 3171 that scrapes Amazon product detail pages
using Scrapling (with fallback to httpx) for full product data collection.

Architecture (v3):
- Task-ID based async tracking (no global scrape_status)
- All endpoints return JSON (no direct DB writes)
- Sync endpoints use def (FastAPI threadpool) for StealthyFetcher compatibility
- Proxy support via PROXY_URL / PROXY_LIST env vars
"""
import os
import json
import time
import uuid
import random
import asyncio
import logging
from typing import Optional

from fastapi import FastAPI, BackgroundTasks, HTTPException
from pydantic import BaseModel

from parsers.images import parse_images
from parsers.overview import parse_overview
from parsers.options import parse_options
from parsers.quantity import parse_quantity
from config import get_proxy, rate_delay, category_pause

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Amazon Scraper", version="3.0.0")

MOCK_MODE = os.environ.get("MOCK_EXTERNAL_APIS", "true").lower() == "true"

# Per-task state: {task_id: {status, total, completed, failed, results, created_at}}
tasks: dict = {}


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

def scrape_with_scrapling(asin: str) -> dict:
    """Scrape a single Amazon product using Scrapling StealthyFetcher."""
    from parsers.product_page import parse_product_page

    try:
        from scrapling.fetchers import StealthyFetcher
        url = f"https://www.amazon.com/dp/{asin}"
        proxy = get_proxy()
        page = StealthyFetcher.fetch(url, headless=True, proxy=proxy)
        return parse_product_page(page, asin=asin)
    except ImportError:
        logger.warning("Scrapling not available, falling back to httpx")
        raise
    except Exception as e:
        logger.warning(f"StealthyFetcher failed for {asin}: {e}, trying Fetcher fallback")
        try:
            from scrapling.fetchers import Fetcher
            page = Fetcher.fetch(f"https://www.amazon.com/dp/{asin}")
            return parse_product_page(page, asin=asin)
        except Exception as e2:
            logger.error(f"All Scrapling fetchers failed for {asin}: {e2}")
            raise


async def scrape_with_httpx(asin: str) -> dict:
    """Fallback: scrape using httpx (legacy method, partial data only)."""
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
                data = scrape_with_scrapling(asin)
            except Exception:
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
    from scrapling.fetchers import StealthyFetcher
    from parsers.bestsellers import parse_bestsellers

    results = []
    for page_num in range(1, pages + 1):
        try:
            url = f"https://www.amazon.com/s?i=specialty-aps&bbn={amazon_node_id}&rh=n%3A{amazon_node_id}&pg={page_num}"
            # Best Sellers URL pattern
            bs_url = f"https://www.amazon.com/gp/bestsellers/{amazon_node_id}/?pg={page_num}"
            delay = rate_delay("amazon")
            await asyncio.sleep(delay)

            proxy = get_proxy()
            page = StealthyFetcher.fetch(bs_url, headless=True, proxy=proxy)
            html = page.body if hasattr(page, "body") else str(page)
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
                data = scrape_with_scrapling(asin)
            except Exception:
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
# Existing endpoints (refactored)
# ---------------------------------------------------------------------------

@app.post("/scrape")
async def start_scrape(req: ScrapeRequest, background_tasks: BackgroundTasks):
    """Start scraping ASINs in background. Returns task_id for polling."""
    cleanup_stale_tasks()
    task_id = new_task(len(req.asins))
    background_tasks.add_task(process_scrape, task_id, req.asins, req.category_id)
    return {"task_id": task_id}


@app.get("/status/{task_id}")
async def get_task_status(task_id: str):
    """Get status of a specific scraping task."""
    if task_id not in tasks:
        raise HTTPException(status_code=404, detail="Task not found")
    return tasks[task_id]


@app.get("/health")
async def health():
    """Health check endpoint."""
    return {"status": "ok", "service": "amazon-scraper", "version": "3.0.0"}


# ---------------------------------------------------------------------------
# New sync endpoints — Amazon BSR / Movers (def, not async def: FastAPI threadpool)
# ---------------------------------------------------------------------------

@app.post("/collect/bsr")
def collect_bsr(req: BsrRequest):
    """Scrape Amazon Best Sellers for a category node. Synchronous."""
    cleanup_stale_tasks()
    from parsers.bestsellers import parse_bestsellers, compute_bsr_stats

    if MOCK_MODE:
        logger.info(f"[MOCK] /collect/bsr called for node {req.amazon_node_id}")
        return {"products": [], "stats": {"avg_bsr": None, "total": 0, "avg_price": None,
                                          "avg_reviews": None, "avg_rating": None,
                                          "fba_ratio": None, "price_in_range_pct": None}}

    try:
        from scrapling.fetchers import StealthyFetcher
        url = f"https://www.amazon.com/gp/bestsellers/{req.amazon_node_id}/"
        proxy = get_proxy()
        page = StealthyFetcher.fetch(url, headless=True, proxy=proxy)
        html = page.body if hasattr(page, "body") else str(page)
        products = parse_bestsellers(html)
        stats = compute_bsr_stats(products)
        logger.info(f"[BSR] Collected {len(products)} products for node {req.amazon_node_id}")
        return {"products": products, "stats": stats}
    except Exception as e:
        logger.error(f"[BSR] Failed for node {req.amazon_node_id}: {e}")
        return {"error": str(e), "products": [], "stats": {}}


@app.post("/collect/movers")
def collect_movers(req: MoversRequest):
    """Scrape Amazon Movers & Shakers for a category node. Synchronous."""
    cleanup_stale_tasks()
    from parsers.movers import parse_movers

    if MOCK_MODE:
        logger.info(f"[MOCK] /collect/movers called for node {req.amazon_node_id}")
        return {"movers": []}

    try:
        from scrapling.fetchers import StealthyFetcher
        url = f"https://www.amazon.com/gp/movers-and-shakers/{req.amazon_node_id}/"
        proxy = get_proxy()
        page = StealthyFetcher.fetch(url, headless=True, proxy=proxy)
        html = page.body if hasattr(page, "body") else str(page)
        movers = parse_movers(html)
        logger.info(f"[Movers] Collected {len(movers)} movers for node {req.amazon_node_id}")
        return {"movers": movers}
    except Exception as e:
        logger.error(f"[Movers] Failed for node {req.amazon_node_id}: {e}")
        return {"error": str(e), "movers": []}


# ---------------------------------------------------------------------------
# New async endpoints — URL collection, Trends, Social, Price resync
# (Trends and Social are stubs here; parsers implemented by worker-3)
# ---------------------------------------------------------------------------

@app.post("/collect/urls")
async def collect_urls(req: UrlsRequest, background_tasks: BackgroundTasks):
    """Collect ASINs from Amazon Best Sellers pages. Returns task_id for polling."""
    cleanup_stale_tasks()
    task_id = new_task(req.pages)
    background_tasks.add_task(process_url_collection, task_id, req.amazon_node_id, req.pages)
    return {"task_id": task_id}


@app.post("/collect/trends")
async def collect_trends(req: TrendsRequest):
    """Collect Google Trends data for keywords (implemented by worker-3 parsers)."""
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
    """Collect Reddit (and approximate TikTok) signals (implemented by worker-3 parsers)."""
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

    port = int(os.environ.get("SCRAPER_PORT", "3171"))
    uvicorn.run(app, host="127.0.0.1", port=port)
