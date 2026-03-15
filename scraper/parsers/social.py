"""Reddit + TikTok social signal fetcher.

Reddit: uses PRAW (official Reddit API, 60 req/min free tier).
TikTok: returns approximate/static data — Kasada anti-bot prevents automation.

Env vars required for Reddit:
  REDDIT_CLIENT_ID
  REDDIT_CLIENT_SECRET
  REDDIT_USER_AGENT (optional, defaults to 'shopdata-scraper/1.0')
"""
import os
import logging
import time

logger = logging.getLogger(__name__)

REDDIT_CLIENT_ID = os.environ.get("REDDIT_CLIENT_ID", "")
REDDIT_CLIENT_SECRET = os.environ.get("REDDIT_CLIENT_SECRET", "")
REDDIT_USER_AGENT = os.environ.get("REDDIT_USER_AGENT", "shopdata-scraper/1.0")

# Rate limit: 1s between Reddit requests (well within 60 req/min)
REDDIT_DELAY = 1


def fetch_social(keywords: list[str], subreddits: list[str] = None) -> dict:
    """Fetch Reddit mentions and sentiment for keywords.

    Args:
        keywords: Search terms to look up on Reddit.
        subreddits: Optional list of subreddits to restrict search.
                    If empty, searches all of Reddit.

    Returns:
        dict with 'reddit' (mentions, sentiment, top_posts) and 'tiktok_views'.
    """
    reddit_data = _fetch_reddit(keywords, subreddits or [])
    tiktok_data = _approximate_tiktok(keywords)

    return {
        "reddit": reddit_data,
        "tiktok_views": tiktok_data,
    }


def _fetch_reddit(keywords: list[str], subreddits: list[str]) -> dict:
    """Fetch Reddit mentions and sentiment via PRAW."""
    if not REDDIT_CLIENT_ID or not REDDIT_CLIENT_SECRET:
        logger.warning("[Social] Reddit credentials not configured (REDDIT_CLIENT_ID / REDDIT_CLIENT_SECRET)")
        return {"mentions": 0, "sentiment": None, "top_posts": [], "error": "credentials not configured"}

    try:
        import praw
        from praw.exceptions import PRAWException
    except ImportError:
        logger.warning("[Social] praw not installed")
        return {"mentions": 0, "sentiment": None, "top_posts": [], "error": "praw not installed"}

    try:
        reddit = praw.Reddit(
            client_id=REDDIT_CLIENT_ID,
            client_secret=REDDIT_CLIENT_SECRET,
            user_agent=REDDIT_USER_AGENT,
        )

        mentions = 0
        top_posts = []
        scores = []

        query = " OR ".join(f'"{kw}"' for kw in keywords) if keywords else ""
        if not query:
            return {"mentions": 0, "sentiment": None, "top_posts": []}

        # Search within specified subreddits or all of Reddit
        if subreddits:
            subreddit_str = "+".join(subreddits)
            search_target = reddit.subreddit(subreddit_str)
        else:
            search_target = reddit.subreddit("all")

        for submission in search_target.search(query, sort="new", time_filter="month", limit=50):
            mentions += 1
            # Score as upvote ratio: >0.7 = positive, <0.4 = negative, else neutral
            ratio = submission.upvote_ratio
            if ratio >= 0.7:
                scores.append(1)
            elif ratio <= 0.4:
                scores.append(-1)
            else:
                scores.append(0)

            if len(top_posts) < 5:
                top_posts.append({
                    "title": submission.title,
                    "score": submission.score,
                    "upvote_ratio": round(ratio, 2),
                    "url": f"https://reddit.com{submission.permalink}",
                    "created_utc": int(submission.created_utc),
                })

            time.sleep(REDDIT_DELAY / 60)  # spread requests within rate limit

        # Aggregate sentiment: mean of scores (-1 to 1 range)
        sentiment = None
        if scores:
            avg = sum(scores) / len(scores)
            if avg > 0.3:
                sentiment = "positive"
            elif avg < -0.3:
                sentiment = "negative"
            else:
                sentiment = "neutral"

        logger.info(f"[Social] Reddit: {mentions} mentions, sentiment={sentiment}")
        return {
            "mentions": mentions,
            "sentiment": sentiment,
            "top_posts": top_posts,
        }

    except Exception as e:
        logger.error(f"[Social] Reddit fetch failed: {e}")
        return {"mentions": 0, "sentiment": None, "top_posts": [], "error": str(e)}


def _approximate_tiktok(keywords: list[str]) -> str:
    """Return approximate TikTok views label.

    TikTok uses Kasada anti-bot which defeats Scrapling/httpx.
    Returns a static approximation label for display purposes.
    Real data requires manual entry or TikTok Business API access.
    """
    # Approximate based on keyword count as a placeholder indicator
    # This signals to the UI that TikTok data is not automated
    return "n/a (manual)"
