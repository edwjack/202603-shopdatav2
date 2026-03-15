"""Google Trends data fetcher via pytrends.

Accepts a list of keywords and returns interest, YoY change, and
coefficient of variation (CV) as a measure of demand stability.
"""
import logging
import time

logger = logging.getLogger(__name__)

# Rate limit: pytrends recommends ~6s between requests to avoid 429s
TRENDS_DELAY = 6


def fetch_trends(keywords: list[str]) -> dict:
    """Fetch Google Trends data for a list of keywords.

    Args:
        keywords: List of search terms to query.

    Returns:
        dict with key 'trends': list of {keyword, interest, yoy_change, cv}
        On error, returns {'trends': [], 'error': str}
    """
    if not keywords:
        return {"trends": []}

    try:
        from pytrends.request import TrendReq
    except ImportError:
        logger.warning("[Trends] pytrends not installed")
        return {"trends": [], "error": "pytrends not installed"}

    try:
        pytrends = TrendReq(hl="en-US", tz=360, timeout=(10, 25))
        results = []

        # Process keywords in batches of 5 (pytrends limit per request)
        for i in range(0, len(keywords), 5):
            batch = keywords[i:i + 5]
            try:
                pytrends.build_payload(batch, timeframe="today 12-m", geo="US")
                interest_df = pytrends.interest_over_time()

                if interest_df.empty:
                    for kw in batch:
                        results.append({"keyword": kw, "interest": None, "yoy_change": None, "cv": None})
                    continue

                for kw in batch:
                    if kw not in interest_df.columns:
                        results.append({"keyword": kw, "interest": None, "yoy_change": None, "cv": None})
                        continue

                    series = interest_df[kw].dropna()
                    if series.empty:
                        results.append({"keyword": kw, "interest": None, "yoy_change": None, "cv": None})
                        continue

                    # Current interest = last 4-week average
                    current_interest = round(float(series.tail(4).mean()), 1)

                    # YoY: compare last 4 weeks vs same period 52 weeks ago
                    yoy_change = None
                    if len(series) >= 52:
                        prev_year = float(series.iloc[-56:-52].mean()) if len(series) >= 56 else float(series.iloc[0:4].mean())
                        if prev_year > 0:
                            yoy_change = round((current_interest - prev_year) / prev_year * 100, 1)

                    # CV = std / mean (lower = more stable demand)
                    cv = None
                    mean_val = float(series.mean())
                    if mean_val > 0:
                        cv = round(float(series.std()) / mean_val, 3)

                    results.append({
                        "keyword": kw,
                        "interest": current_interest,
                        "yoy_change": yoy_change,
                        "cv": cv,
                    })

                # Rate limit between batches
                if i + 5 < len(keywords):
                    time.sleep(TRENDS_DELAY)

            except Exception as e:
                logger.error(f"[Trends] Batch {batch} failed: {e}")
                for kw in batch:
                    results.append({"keyword": kw, "interest": None, "yoy_change": None, "cv": None, "error": str(e)})

        return {"trends": results}

    except Exception as e:
        logger.error(f"[Trends] fetch_trends failed: {e}")
        return {"trends": [], "error": str(e)}
