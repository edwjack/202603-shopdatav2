"""Parse Amazon product quantity/availability from detail page HTML."""
import re

from scrapling.parser import Selector


def parse_quantity(html: str) -> int:
    """Extract product stock quantity from Amazon HTML.

    Returns estimated quantity. 0 means out of stock.
    """
    tree = Selector(html)

    # Check availability text
    avail = tree.css("#availability").first
    if avail:
        text = avail.text.strip().lower() if avail else ''
        if "currently unavailable" in text or "out of stock" in text:
            return 0
        if "in stock" in text:
            # Try to find specific count
            match = re.search(r"only (\d+) left", text)
            if match:
                return int(match.group(1))
            return 100  # "In Stock" without count = assume plenty

    # Check quantity dropdown
    qty_select = tree.css("#quantity select, #quantityDropdownContainer select").first
    if qty_select:
        options = qty_select.css("option")
        if options:
            try:
                return max(int(opt.attrib.get("value", "0")) for opt in options)
            except (ValueError, TypeError):
                pass

    # Check add-to-cart button existence
    add_to_cart = tree.css("#add-to-cart-button").first
    if add_to_cart:
        return 50  # Has add to cart = in stock

    return 0
