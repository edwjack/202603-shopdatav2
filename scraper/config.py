"""Configurable rate limits and scraper settings.

Anti-bot strategy:
- Amazon requests use Gaussian-distributed delays (12-25s default) to mimic human browsing
- Category pauses (3-5 min) between batch scrapes reduce velocity fingerprinting
- Uniform delays for API-based sources (Trends, Reddit) where anti-bot is minimal
"""
import os
import random
import math

RATE_LIMITS = {
    "amazon": {
        "min_delay": float(os.environ.get("AMAZON_DELAY_MIN", "12")),
        "max_delay": float(os.environ.get("AMAZON_DELAY_MAX", "25")),
        "mean": float(os.environ.get("AMAZON_DELAY_MEAN", "18")),
        "stddev": float(os.environ.get("AMAZON_DELAY_STDDEV", "4")),
    },
    "trends": {
        "min_delay": float(os.environ.get("TRENDS_DELAY_MIN", "6")),
        "max_delay": float(os.environ.get("TRENDS_DELAY_MAX", "6")),
    },
    "reddit": {
        "min_delay": float(os.environ.get("REDDIT_DELAY_MIN", "1")),
        "max_delay": float(os.environ.get("REDDIT_DELAY_MAX", "1")),
    },
}

# Pause between categories during batch scraping (seconds)
CATEGORY_PAUSE_MIN = float(os.environ.get("CATEGORY_PAUSE_MIN", "180"))  # 3 minutes
CATEGORY_PAUSE_MAX = float(os.environ.get("CATEGORY_PAUSE_MAX", "300"))  # 5 minutes

PROXY_URL = os.environ.get("PROXY_URL")
PROXY_LIST = [p for p in os.environ.get("PROXY_LIST", "").split(",") if p]


def get_proxy():
    """Return a proxy URL from env config, or None if not configured."""
    if PROXY_LIST:
        return random.choice(PROXY_LIST)
    return PROXY_URL


def rate_delay(source: str) -> float:
    """Return a random delay for the given source.

    Amazon uses Gaussian distribution (more human-like).
    Other sources use uniform distribution.
    """
    limits = RATE_LIMITS.get(source, {"min_delay": 2, "max_delay": 5})

    if "mean" in limits and "stddev" in limits:
        # Gaussian delay — clamped to [min, max]
        delay = random.gauss(limits["mean"], limits["stddev"])
        return max(limits["min_delay"], min(limits["max_delay"], delay))

    # Uniform delay for non-Amazon sources
    return random.uniform(limits["min_delay"], limits["max_delay"])


def category_pause() -> float:
    """Return a random pause duration (seconds) between category batches."""
    return random.uniform(CATEGORY_PAUSE_MIN, CATEGORY_PAUSE_MAX)
