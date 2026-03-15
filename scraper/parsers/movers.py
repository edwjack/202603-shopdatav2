"""Amazon Movers & Shakers page parser.

Accepts raw HTML string (not Scrapling page objects) for testability.
Parses the Movers & Shakers grid: title, ASIN, BSR change %, price.
"""
import re
from typing import Optional
from selectolax.parser import HTMLParser


def parse_movers(html: str) -> list[dict]:
    """Parse Amazon Movers & Shakers page HTML into a list of mover dicts.

    Args:
        html: Raw HTML string from the Movers & Shakers page.

    Returns:
        List of dicts with keys: asin, title, bsr_change_pct, price.
    """
    tree = HTMLParser(html)
    movers = []

    # Movers & Shakers uses similar grid to Best Sellers
    items = tree.css('[data-asin]')
    if not items:
        items = tree.css('li.zg-item-immersion')

    seen_asins = set()
    for item in items:
        asin = item.attributes.get('data-asin', '').strip()
        if not asin or asin in seen_asins:
            continue
        seen_asins.add(asin)

        title = _text(item, '.p13n-sc-truncate-desktop-type2, .p13n-sc-truncated, a.a-link-normal span')
        bsr_change_pct = _parse_bsr_change(item)
        price = _parse_price(item)

        movers.append({
            'asin': asin,
            'title': title,
            'bsr_change_pct': bsr_change_pct,
            'price': price,
        })

    return movers


def _text(node, selector: str) -> str:
    """Extract stripped text from first matching CSS selector within node."""
    try:
        el = node.css_first(selector)
        return el.text(strip=True) if el else ''
    except Exception:
        return ''


def _parse_bsr_change(item) -> Optional[float]:
    """Parse BSR change percentage from mover item node.

    Amazon shows change as e.g. '▲ 1,234%' or '▼ 567%'.
    Returns positive float for increases (movers up in rank = lower rank number).
    """
    # Common selectors for rank change display
    selectors = [
        '.zg-bdg-text',
        'span[class*="change"]',
        '.a-color-success',
        '.a-color-price',
    ]
    for sel in selectors:
        el = item.css_first(sel)
        if el:
            text = el.text(strip=True)
            # Look for percentage pattern like "1,234%"
            match = re.search(r'([\d,]+)%', text)
            if match:
                try:
                    pct = float(match.group(1).replace(',', ''))
                    # Negative arrow (▼) means rank got worse
                    if '▼' in text or 'down' in text.lower():
                        pct = -pct
                    return pct
                except ValueError:
                    pass
    return None


def _parse_price(item) -> float:
    """Parse price from mover item node."""
    price_el = item.css_first('.a-price .a-offscreen, ._cDEzb_p13n-sc-price_3mJ9Z')
    if price_el:
        text = price_el.text(strip=True).replace(',', '')
        match = re.search(r'[\d.]+', text)
        if match:
            try:
                return float(match.group())
            except ValueError:
                pass
    return 0.0
