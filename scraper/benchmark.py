"""3-Channel Scraping Benchmark — test 50 ASINs per channel and compare performance.

Usage:
    # DIRECT only (no proxy needed):
    python benchmark.py --channels direct --count 50

    # All 3 channels (requires proxy env vars):
    python benchmark.py --channels direct,decodo,smart --count 50

    # Quick test:
    python benchmark.py --channels direct --count 5

Outputs: performance comparison table + Shopify-ready JSON samples
"""
import asyncio
import argparse
import json
import logging
import os
import re
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime

# Add parent dir to path for imports
sys.path.insert(0, os.path.dirname(__file__))

from session_manager import SessionManager
from parsers.product_page import parse_product_page
from shopify_mapper import to_shopify_product
from config import rate_delay

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
logger = logging.getLogger(__name__)

# Sample ASINs for benchmarking — non-gated brands from Best Sellers
# Categories: kitchen, sports, tools ($30-80 target range)
SAMPLE_ASINS = [
    "B07PZF3QS3", "B0C6Y8NYK1", "B07984JN3L", "B0113UZJE2", "B0B2P4P2R4",
    "B0F5X4FM3Q", "B0CHGFG64S", "B01FHOWYA2", "B07WMQP4SF", "B08N9Q24M9",
    "B0CP9YB3Q4", "B0C3QZ7SNF", "B0D3W6XGLR", "B0BZYCJK89", "B0CJF94M8J",
    "B0CHTVMXZJ", "B0CMP9M725", "B0FJZP9J1V", "B0CVNCHMFM", "B08MY13HYC",
    "B074DZ5YL9", "B01N1HEY0M", "B08XQ35T47", "B0D343X9V2", "B0B7CJT5SP",
    "B07XYYBHFK", "B0FJN3BTPV", "B0CK2JCYRK", "B0DHT5XZR1", "B074P8MZW9",
    "B09V366BDY", "B09YKX9DS7", "B009PCI2JU", "B0BZWRSRWV", "B01MUBU0YC",
    "B0B27HX6P7", "B0B3SR5M71", "B0C3SSXL4K", "B0DFPQ4VY8", "B0BDF8CVBN",
    "B09N6XCCQH", "B004Q6D02E", "B0882ZJ48W", "B07JHQ4L4F",
]


@dataclass
class ChannelResult:
    """Benchmark results for one channel."""
    channel: str
    total_asins: int = 0
    success: int = 0
    failed: int = 0
    blocked: int = 0
    total_time_s: float = 0
    avg_response_ms: float = 0
    min_response_ms: float = float("inf")
    max_response_ms: float = 0
    response_times: list = field(default_factory=list)
    products: list = field(default_factory=list)
    shopify_products: list = field(default_factory=list)
    errors: list = field(default_factory=list)


BLOCK_SIGNALS = [
    "api-services-support@amazon.com",
    "Type the characters you see in this image",
    "Sorry, we just need to make sure you're not a robot",
    "automated access to Amazon",
]


def is_blocked(html: str) -> bool:
    html_lower = html.lower()
    return any(s.lower() in html_lower for s in BLOCK_SIGNALS)


async def benchmark_channel(channel: str, asins: list[str], proxy_url: str = None) -> ChannelResult:
    """Benchmark a single channel by scraping N ASINs."""
    result = ChannelResult(channel=channel, total_asins=len(asins))
    session = SessionManager()

    logger.info(f"[{channel.upper()}] Starting benchmark with {len(asins)} ASINs (proxy={'yes' if proxy_url else 'no'})")

    try:
        await session.start()
        start_time = time.time()

        for i, asin in enumerate(asins):
            if not re.fullmatch(r'[A-Z0-9]{10}', asin):
                result.failed += 1
                result.errors.append(f"{asin}: invalid format")
                continue

            # Adaptive delay (human-like)
            delay = rate_delay("amazon")
            await asyncio.sleep(delay)

            url = f"https://www.amazon.com/dp/{asin}"
            req_start = time.time()

            try:
                page = await session.fetch(url, network_idle=True)
                req_ms = (time.time() - req_start) * 1000

                html = page.body if hasattr(page, 'body') else str(page)
                if isinstance(html, bytes):
                    html = html.decode('utf-8', errors='replace')

                # Check HTTP status via page attributes
                page_status = getattr(page, 'status', 200)
                if page_status == 404:
                    result.failed += 1
                    result.errors.append(f"{asin}: 404 not found")
                    logger.warning(f"[{channel.upper()}] 404 on {asin} ({i+1}/{len(asins)})")
                    continue

                if is_blocked(html):
                    result.blocked += 1
                    result.errors.append(f"{asin}: BLOCKED by Amazon")
                    logger.warning(f"[{channel.upper()}] BLOCKED on {asin} ({i+1}/{len(asins)})")
                    continue

                data = parse_product_page(page, asin=asin)
                shopify = to_shopify_product(data, margin_rate=50.0)

                result.success += 1
                result.products.append(data)
                result.shopify_products.append(shopify)
                result.response_times.append(req_ms)
                result.min_response_ms = min(result.min_response_ms, req_ms)
                result.max_response_ms = max(result.max_response_ms, req_ms)

                title_preview = (data.get("title", "") or "")[:50]
                price = data.get("price", 0)
                logger.info(
                    f"[{channel.upper()}] {i+1}/{len(asins)} OK "
                    f"{asin} ${price} {req_ms:.0f}ms — {title_preview}"
                )

            except Exception as e:
                req_ms = (time.time() - req_start) * 1000
                result.failed += 1
                result.errors.append(f"{asin}: {str(e)[:100]}")
                logger.error(f"[{channel.upper()}] {i+1}/{len(asins)} FAIL {asin}: {e}")

        result.total_time_s = time.time() - start_time

    finally:
        await session.stop()

    # Compute averages
    if result.response_times:
        result.avg_response_ms = sum(result.response_times) / len(result.response_times)
    if result.min_response_ms == float("inf"):
        result.min_response_ms = 0

    return result


def print_comparison_table(results: list[ChannelResult]):
    """Print performance comparison table."""
    print("\n" + "=" * 90)
    print("  3-CHANNEL SCRAPING BENCHMARK — PERFORMANCE COMPARISON")
    print("=" * 90)

    header = (
        f"{'Channel':<12} {'Total':>6} {'OK':>5} {'Fail':>5} {'Block':>6} "
        f"{'Time':>8} {'Avg ms':>8} {'Min ms':>8} {'Max ms':>8} {'Rate':>8}"
    )
    print(header)
    print("-" * 90)

    for r in results:
        success_rate = f"{r.success/r.total_asins*100:.0f}%" if r.total_asins > 0 else "N/A"
        rate_per_hr = f"{r.success / (r.total_time_s / 3600):.0f}/hr" if r.total_time_s > 0 and r.success > 0 else "N/A"
        print(
            f"{r.channel.upper():<12} {r.total_asins:>6} {r.success:>5} {r.failed:>5} {r.blocked:>6} "
            f"{r.total_time_s:>7.0f}s {r.avg_response_ms:>7.0f} {r.min_response_ms:>7.0f} {r.max_response_ms:>7.0f} "
            f"{rate_per_hr:>8}"
        )

    print("-" * 90)

    # Data quality comparison
    print(f"\n{'Channel':<12} {'Has Title':>10} {'Has Price':>10} {'Has Brand':>10} {'Has Image':>10} {'Avg Fields':>10}")
    print("-" * 65)

    for r in results:
        if not r.products:
            print(f"{r.channel.upper():<12} {'N/A':>10} {'N/A':>10} {'N/A':>10} {'N/A':>10} {'N/A':>10}")
            continue

        has_title = sum(1 for p in r.products if p.get("title")) / len(r.products) * 100
        has_price = sum(1 for p in r.products if p.get("price", 0) > 0) / len(r.products) * 100
        has_brand = sum(1 for p in r.products if p.get("brand")) / len(r.products) * 100
        has_image = sum(1 for p in r.products if p.get("images")) / len(r.products) * 100
        avg_fields = sum(
            sum(1 for v in p.values() if v and v != 0 and v != [] and v != {})
            for p in r.products
        ) / len(r.products)

        print(
            f"{r.channel.upper():<12} {has_title:>9.0f}% {has_price:>9.0f}% "
            f"{has_brand:>9.0f}% {has_image:>9.0f}% {avg_fields:>9.1f}"
        )

    print("-" * 65)

    # Cost estimate
    print(f"\n{'Channel':<12} {'Cost/50':>10} {'Cost/5K':>10} {'Cost/50K':>10}")
    print("-" * 45)
    for r in results:
        if r.channel == "direct":
            print(f"{r.channel.upper():<12} {'$0':>10} {'$0':>10} {'$0':>10}")
        else:
            # ~2MB per page, $2.20/GB (Decodo) or $2.00/GB (Smart)
            rate = 2.20 if r.channel == "decodo" else 2.00
            cost_50 = 50 * 2 / 1024 * rate
            cost_5k = 5000 * 2 / 1024 * rate
            cost_50k = 50000 * 2 / 1024 * rate
            print(
                f"{r.channel.upper():<12} ${cost_50:>8.2f} ${cost_5k:>8.1f} ${cost_50k:>8.0f}"
            )

    print("=" * 90)


def save_results(results: list[ChannelResult], output_dir: str = "scraper/data/benchmark"):
    """Save benchmark results and Shopify-ready samples."""
    os.makedirs(output_dir, exist_ok=True)
    timestamp = datetime.utcnow().strftime("%Y%m%d-%H%M%S")

    for r in results:
        # Performance summary
        summary = {
            "channel": r.channel,
            "timestamp": timestamp,
            "total": r.total_asins,
            "success": r.success,
            "failed": r.failed,
            "blocked": r.blocked,
            "total_time_s": round(r.total_time_s, 1),
            "avg_response_ms": round(r.avg_response_ms, 0),
            "min_response_ms": round(r.min_response_ms, 0),
            "max_response_ms": round(r.max_response_ms, 0),
            "errors": r.errors[:10],
        }

        path = os.path.join(output_dir, f"{timestamp}-{r.channel}-summary.json")
        with open(path, "w") as f:
            json.dump(summary, f, indent=2, ensure_ascii=False)
        logger.info(f"Summary saved: {path}")

        # Shopify-ready products (first 5 as samples)
        if r.shopify_products:
            samples_path = os.path.join(output_dir, f"{timestamp}-{r.channel}-shopify-samples.json")
            with open(samples_path, "w") as f:
                json.dump(r.shopify_products[:5], f, indent=2, ensure_ascii=False)
            logger.info(f"Shopify samples saved: {samples_path}")

            # Full Shopify export
            full_path = os.path.join(output_dir, f"{timestamp}-{r.channel}-shopify-full.json")
            with open(full_path, "w") as f:
                json.dump(r.shopify_products, f, indent=2, ensure_ascii=False)
            logger.info(f"Shopify full export saved: {full_path}")

    # Combined comparison
    comparison_path = os.path.join(output_dir, f"{timestamp}-comparison.json")
    comparison = {
        "timestamp": timestamp,
        "channels": [
            {
                "channel": r.channel,
                "success_rate": round(r.success / r.total_asins * 100, 1) if r.total_asins else 0,
                "throughput_per_hr": round(r.success / (r.total_time_s / 3600)) if r.total_time_s > 0 and r.success > 0 else 0,
                "avg_response_ms": round(r.avg_response_ms),
                "blocked_count": r.blocked,
            }
            for r in results
        ],
    }
    with open(comparison_path, "w") as f:
        json.dump(comparison, f, indent=2, ensure_ascii=False)
    logger.info(f"Comparison saved: {comparison_path}")


async def main():
    parser = argparse.ArgumentParser(description="3-Channel Scraping Benchmark")
    parser.add_argument("--channels", default="direct", help="Channels to test: direct,decodo,smart (comma-separated)")
    parser.add_argument("--count", type=int, default=50, help="ASINs per channel (default 50)")
    parser.add_argument("--save", action="store_true", default=True, help="Save results to scraper/data/benchmark/")
    args = parser.parse_args()

    channels = [c.strip() for c in args.channels.split(",")]
    count = min(args.count, len(SAMPLE_ASINS))
    asins = SAMPLE_ASINS[:count]

    proxy_map = {
        "direct": None,
        "decodo": os.environ.get("DECODO_PROXY_URL"),
        "smart": os.environ.get("SMARTPROXY_URL"),
    }

    # Validate channels
    for ch in channels:
        if ch not in proxy_map:
            logger.error(f"Unknown channel: {ch}. Use: direct, decodo, smart")
            return
        if ch != "direct" and not proxy_map[ch]:
            logger.warning(f"Channel {ch} has no proxy URL configured. Set {ch.upper()}_PROXY_URL env var.")

    results = []
    for ch in channels:
        result = await benchmark_channel(ch, asins, proxy_url=proxy_map.get(ch))
        results.append(result)

    print_comparison_table(results)

    if args.save:
        save_results(results)
        print(f"\nResults saved to scraper/data/benchmark/")

    # Print a Shopify sample
    if results and results[0].shopify_products:
        print("\n--- SHOPIFY PRODUCT SAMPLE (first product) ---")
        print(json.dumps(results[0].shopify_products[0], indent=2, ensure_ascii=False)[:2000])
        print("---")


if __name__ == "__main__":
    asyncio.run(main())
