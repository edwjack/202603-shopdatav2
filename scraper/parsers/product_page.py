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
    if isinstance(html, bytes):
        html = html.decode('utf-8', errors='replace')

    return {
        'asin': asin,
        'title': _text(page, '#productTitle'),
        'price': _parse_price(page, html),
        'brand': _parse_brand(page),
        'review_rating': _parse_float(_text(page, '#acrPopover .a-color-base')),
        'review_count': _parse_review_count(page),
        'about_this': _parse_about_this(page),
        'tags': [],  # Amazon pages don't expose tags directly
        'category_name': _text(page, '#wayfinding-breadcrumbs_feature_div li:last-child a'),
        # Use page object for images (DOM + JSON), html string for legacy parsers
        'images': _parse_images_from_page(page, html),
        'overview': parse_overview(html),
        'options': parse_options(html),
        'quantity': parse_quantity(html),
    }


def _text(page, selector: str) -> str:
    """Safely extract text from first matching CSS selector."""
    try:
        el = page.css(selector).first
        return el.text.strip() if el else ''
    except Exception:
        return ''


def _parse_price(page, html: str = "") -> float:
    """Extract price from Amazon price elements.

    Strategy: try CSS selectors first (broadened set), then regex on raw HTML.
    Amazon sometimes hides price from CSS but leaves it in data attributes or scripts.
    """
    selectors = [
        '.a-price .a-offscreen',
        '.priceToPay .a-offscreen',
        '#corePrice_feature_div .a-price .a-offscreen',
        '#corePriceDisplay_desktop_feature_div .a-price .a-offscreen',
        '#priceblock_ourprice',
        '#priceblock_dealprice',
        '.a-price-whole',
        '#buyNewSection .a-price .a-offscreen',
        '#newBuyBoxPrice',
        '.offer-price',
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

    # Fallback: regex on raw HTML for any dollar amount
    if html:
        # Look for price patterns in data attributes or structured data
        price_matches = re.findall(r'\$(\d{1,4}(?:,\d{3})*\.\d{2})', html)
        if price_matches:
            try:
                return float(price_matches[0].replace(',', ''))
            except ValueError:
                pass

        # JSON-LD structured data (schema.org)
        ld_match = re.search(r'"price"\s*:\s*"?(\d+\.?\d*)"?', html)
        if ld_match:
            try:
                return float(ld_match.group(1))
            except ValueError:
                pass

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


def _parse_images_from_page(page, html: str = "") -> list[dict]:
    """Extract product images using DOM selectors + JSON fallback.

    Strategy:
    1. DOM: data-old-hires attributes from .a-dynamic-image elements (highest quality)
    2. DOM: #landingImage src as main image
    3. DOM: #altImages thumbnails, upscale URL pattern
    4. JSON: hiRes URLs from colorImages/imageGalleryData in script tags
    5. Fallback: legacy parse_images() regex on raw HTML
    """
    images = []
    seen_urls = set()

    def _add(url: str, variant: str = "MAIN"):
        if url and url.startswith("http") and url not in seen_urls:
            # Skip tiny thumbnails (SR38,50 etc)
            if '_SR38,' in url or '_SS40' in url or '_CR0,0,38' in url:
                return
            seen_urls.add(url)
            images.append({"hiRes": url, "variant": variant})

    # 1. data-old-hires from dynamic image elements (best quality)
    try:
        dynamic_imgs = page.css('.a-dynamic-image')
        for el in (dynamic_imgs or []):
            hires = ''
            if hasattr(el, 'attrib'):
                hires = el.attrib.get('data-old-hires', '')
            elif hasattr(el, 'attributes'):
                hires = el.attributes.get('data-old-hires', '')
            if hires:
                _add(hires)
    except Exception:
        pass

    # 2. Landing image
    try:
        landing = page.css('#landingImage').first
        if landing:
            src = ''
            hires = ''
            if hasattr(landing, 'attrib'):
                src = landing.attrib.get('src', '')
                hires = landing.attrib.get('data-old-hires', '')
            elif hasattr(landing, 'attributes'):
                src = landing.attributes.get('src', '')
                hires = landing.attributes.get('data-old-hires', '')
            _add(hires or src)
    except Exception:
        pass

    # 3. JSON hiRes from script tags (most reliable for full gallery)
    if html:
        try:
            hires_urls = re.findall(r'"hiRes":"(https://m\.media-amazon\.com/images/I/[^"]+)"', html)
            for i, url in enumerate(hires_urls):
                _add(url, variant="MAIN" if i == 0 else f"PT{i:02d}")
        except Exception:
            pass

    # 4. Fallback to legacy parser
    if not images:
        legacy = parse_images(html)
        for item in legacy:
            url = item.get("hiRes") or item.get("large") or ""
            _add(url, item.get("variant", "MAIN"))

    return images


def _parse_about_this(page) -> list:
    """Extract 'About this item' bullet points."""
    items = []
    try:
        bullets = page.css('#feature-bullets li span.a-list-item')
        for bullet in (bullets or []):
            text = bullet.text.strip() if bullet else ''
            if text and not text.startswith('Make sure') and len(text) > 5:
                items.append(text)
    except Exception:
        pass
    return items
