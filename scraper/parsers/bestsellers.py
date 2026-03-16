"""Amazon Best Sellers page parser.

Accepts raw HTML string (not Scrapling page objects) for testability.
Parses the Best Sellers grid: rank, title, ASIN, price, reviews, rating.
"""
import re
from typing import Optional
from scrapling.parser import Selector


def parse_bestsellers(html: str) -> list[dict]:
    """Parse Amazon Best Sellers page HTML into a list of product dicts.

    Args:
        html: Raw HTML string from the Best Sellers page.

    Returns:
        List of dicts with keys: asin, title, rank, price, reviews, rating.
    """
    tree = Selector(html)
    products = []

    # Two common grid containers: zg-grid-general-faceout and zg-item-immersion
    items = tree.css('[data-asin]')
    if not items:
        # Fallback: older layout uses li.zg-item-immersion
        items = tree.css('li.zg-item-immersion')

    seen_asins = set()
    for item in items:
        asin = item.attrib.get('data-asin', '').strip()
        if not asin or asin in seen_asins:
            continue
        seen_asins.add(asin)

        rank = _parse_rank(item)
        title = _text(item, '.p13n-sc-truncate-desktop-type2, .p13n-sc-truncated, a.a-link-normal span')
        price = _parse_price(item)
        rating, reviews = _parse_rating_reviews(item)

        products.append({
            'asin': asin,
            'title': title,
            'bsr_rank': rank,
            'price': price,
            'rating': rating,
            'reviews': reviews,
        })

    return products


def _text(node, selector: str) -> str:
    """Extract stripped text from first matching CSS selector within node."""
    try:
        el = node.css(selector).first
        return el.text.strip() if el else ''
    except Exception:
        return ''


def _parse_rank(item) -> Optional[int]:
    """Parse BSR rank from item node."""
    rank_el = item.css('.zg-bdg-text, span.zg-bdg-text').first
    if rank_el:
        text = rank_el.text.strip().lstrip('#').replace(',', '')
        try:
            return int(text)
        except ValueError:
            pass
    return None


def _parse_price(item) -> float:
    """Parse price from item node."""
    price_el = item.css('.a-price .a-offscreen, ._cDEzb_p13n-sc-price_3mJ9Z').first
    if price_el:
        text = price_el.text.strip().replace(',', '')
        match = re.search(r'[\d.]+', text)
        if match:
            try:
                return float(match.group())
            except ValueError:
                pass
    return 0.0


def _parse_rating_reviews(item) -> tuple[float, int]:
    """Parse rating and review count from item node."""
    rating = 0.0
    reviews = 0

    rating_el = item.css('.a-icon-alt').first
    if rating_el:
        text = rating_el.text.strip()
        match = re.search(r'([\d.]+)\s+out of', text)
        if match:
            try:
                rating = float(match.group(1))
            except ValueError:
                pass

    review_el = item.css('a[href*="customerReviews"] span, .a-size-small.a-link-normal').first
    if review_el:
        text = review_el.text.strip().replace(',', '')
        match = re.search(r'[\d]+', text)
        if match:
            try:
                reviews = int(match.group())
            except ValueError:
                pass

    return rating, reviews


def compute_bsr_stats(products: list[dict], price_min: float = 0, price_max: float = 9999) -> dict:
    """Compute aggregate stats from a list of BSR products.

    Args:
        products: List from parse_bestsellers().
        price_min: Minimum acceptable price for price_in_range_pct.
        price_max: Maximum acceptable price for price_in_range_pct.

    Returns:
        dict with avg_bsr, avg_price, avg_reviews, avg_rating, total, fba_ratio, price_in_range_pct.
    """
    if not products:
        return {
            'avg_bsr': None,
            'avg_price': None,
            'avg_reviews': None,
            'avg_rating': None,
            'total': 0,
            'fba_ratio': None,
            'price_in_range_pct': None,
        }

    total = len(products)
    ranks = [p['bsr_rank'] for p in products if p.get('bsr_rank') is not None]
    prices = [p['price'] for p in products if p.get('price', 0) > 0]
    reviews_list = [p['reviews'] for p in products if p.get('reviews', 0) > 0]
    ratings = [p['rating'] for p in products if p.get('rating', 0) > 0]
    in_range = [p for p in products if price_min <= p.get('price', 0) <= price_max and p.get('price', 0) > 0]

    return {
        'avg_bsr': round(sum(ranks) / len(ranks), 1) if ranks else None,
        'avg_price': round(sum(prices) / len(prices), 2) if prices else None,
        'avg_reviews': round(sum(reviews_list) / len(reviews_list), 0) if reviews_list else None,
        'avg_rating': round(sum(ratings) / len(ratings), 2) if ratings else None,
        'total': total,
        'fba_ratio': None,  # FBA detection requires product detail page scraping
        'price_in_range_pct': round(len(in_range) / total * 100, 1) if total > 0 else None,
    }
