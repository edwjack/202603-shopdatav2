"""Unified Amazon product page parser using Scrapling.

Combines basic product info extraction (via Scrapling CSS selectors)
with existing parsers (images, overview, options, quantity) that accept html: str.
"""
import re

from parsers.images import parse_images
from parsers.overview import parse_overview
from parsers.options import parse_options
from parsers.quantity import parse_quantity


def parse_product_page(page, asin: str) -> dict:
    """Parse a Scrapling page object into a unified 13-field product dict.

    Args:
        page: Scrapling Adaptor/page object with .css() and .body/.html
        asin: The ASIN being scraped

    Returns:
        dict with 13 fields for Product model
    """
    # Get raw HTML string for existing parsers (interface compatibility)
    html = page.body if hasattr(page, 'body') else str(page)

    return {
        'asin': asin,
        'title': _text(page, '#productTitle'),
        'price': _parse_price(page),
        'brand': _parse_brand(page),
        'review_rating': _parse_float(_text(page, '#acrPopover .a-color-base')),
        'review_count': _parse_review_count(page),
        'about_this': _parse_about_this(page),
        'tags': [],  # Amazon pages don't expose tags directly
        'category_name': _text(page, '#wayfinding-breadcrumbs_feature_div li:last-child a'),
        # Delegate to existing parsers with html string
        'images': parse_images(html),
        'overview': parse_overview(html),
        'options': parse_options(html),
        'quantity': parse_quantity(html),
    }


def _text(page, selector: str) -> str:
    """Safely extract text from first matching CSS selector."""
    try:
        el = page.css_first(selector)
        return el.text(strip=True) if el else ''
    except Exception:
        return ''


def _parse_price(page) -> float:
    """Extract price from Amazon price elements."""
    selectors = [
        '.a-price .a-offscreen',
        '#priceblock_ourprice',
        '#priceblock_dealprice',
        '.a-price-whole',
    ]
    for sel in selectors:
        text = _text(page, sel)
        if text:
            match = re.search(r'[\d.]+', text.replace(',', ''))
            if match:
                try:
                    return float(match.group())
                except ValueError:
                    continue
    return 0.0


def _parse_brand(page) -> str:
    """Extract brand from multiple possible locations."""
    brand = _text(page, '#bylineInfo')
    if brand:
        brand = re.sub(r'^(Visit the |Brand:\s*)', '', brand)
        brand = re.sub(r'\s*Store$', '', brand)
        return brand.strip()
    return ''


def _parse_float(text: str) -> float:
    """Parse float from text like '4.5 out of 5'."""
    if not text:
        return 0.0
    match = re.search(r'[\d.]+', text)
    if match:
        try:
            return float(match.group())
        except ValueError:
            pass
    return 0.0


def _parse_review_count(page) -> int:
    """Parse review count from text like '3,241 ratings'."""
    text = _text(page, '#acrCustomerReviewText')
    if not text:
        return 0
    match = re.search(r'[\d,]+', text)
    if match:
        try:
            return int(match.group().replace(',', ''))
        except ValueError:
            pass
    return 0


def _parse_about_this(page) -> list:
    """Extract 'About this item' bullet points."""
    items = []
    try:
        bullets = page.css('#feature-bullets li span.a-list-item')
        for bullet in (bullets or []):
            text = bullet.text(strip=True) if bullet else ''
            if text and not text.startswith('Make sure') and len(text) > 5:
                items.append(text)
    except Exception:
        pass
    return items
