"""Map scraped Amazon product data to Shopify Product API format.

Shopify Admin API (2025-01) product structure:
https://shopify.dev/docs/api/admin-rest/2025-01/resources/product

Input:  13-field dict from parse_product_page()
Output: Shopify-compatible product dict ready for POST /admin/api/2025-01/products.json
"""
import json
import re
from typing import Optional


def to_shopify_product(data: dict, category_slug: str = "", margin_rate: float = 50.0) -> dict:
    """Transform scraped Amazon data to Shopify Product API format.

    Args:
        data: Product dict from parse_product_page() with 13 fields
        category_slug: Category slug for product_type
        margin_rate: Markup percentage (default 50% = 1.5x price)

    Returns:
        dict compatible with Shopify POST /admin/api/2025-01/products.json
    """
    # Price with margin
    amazon_price = float(data.get("price", 0) or 0)
    shopify_price = round(amazon_price * (1 + margin_rate / 100), 2) if amazon_price > 0 else 0

    # Body HTML from about_this bullet points
    about = data.get("about_this", [])
    if isinstance(about, str):
        try:
            about = json.loads(about)
        except (json.JSONDecodeError, TypeError):
            about = [about] if about else []

    body_html = _build_body_html(about, data.get("overview", []))

    # Images
    images = data.get("images", [])
    if isinstance(images, str):
        try:
            images = json.loads(images)
        except (json.JSONDecodeError, TypeError):
            images = []

    # Images can be list of strings OR list of dicts with "hiRes" key
    shopify_images = []
    for img in images:
        if isinstance(img, str) and img.startswith("http"):
            shopify_images.append({"src": img})
        elif isinstance(img, dict):
            url = img.get("hiRes") or img.get("large") or img.get("src") or ""
            if url.startswith("http"):
                shopify_images.append({"src": url})

    # Tags
    tags = data.get("tags", [])
    if isinstance(tags, str):
        try:
            tags = json.loads(tags)
        except (json.JSONDecodeError, TypeError):
            tags = []
    tags_str = ", ".join(tags) if tags else ""

    # Options and variants
    options_data = data.get("options", {})
    if isinstance(options_data, str):
        try:
            options_data = json.loads(options_data)
        except (json.JSONDecodeError, TypeError):
            options_data = {}

    shopify_options, shopify_variants = _build_variants(options_data, shopify_price, data.get("asin", ""))

    # Base product
    product = {
        "product": {
            "title": _clean_title(data.get("title", "")),
            "body_html": body_html,
            "vendor": data.get("brand", ""),
            "product_type": category_slug or data.get("category_name", ""),
            "tags": tags_str,
            "status": "draft",  # Always draft initially
            "images": shopify_images[:10],  # Shopify max 250 but keep reasonable
            "variants": shopify_variants,
            "metafields": [
                {
                    "namespace": "amazon",
                    "key": "asin",
                    "value": data.get("asin", ""),
                    "type": "single_line_text_field",
                },
                {
                    "namespace": "amazon",
                    "key": "review_rating",
                    "value": str(data.get("review_rating", 0)),
                    "type": "number_decimal",
                },
                {
                    "namespace": "amazon",
                    "key": "review_count",
                    "value": str(data.get("review_count", 0)),
                    "type": "number_integer",
                },
                {
                    "namespace": "amazon",
                    "key": "amazon_price",
                    "value": str(amazon_price),
                    "type": "number_decimal",
                },
            ],
        }
    }

    if shopify_options:
        product["product"]["options"] = shopify_options

    return product


def _clean_title(title: str) -> str:
    """Clean Amazon title for Shopify (remove excessive length, special chars)."""
    if not title:
        return ""
    # Remove common Amazon title noise
    title = re.sub(r'\s+', ' ', title).strip()
    # Shopify title limit is 255 chars
    return title[:255]


def _build_body_html(about: list, overview: list) -> str:
    """Build Shopify body_html from about_this bullets and overview specs."""
    parts = []

    if about:
        parts.append("<h3>About This Item</h3>")
        parts.append("<ul>")
        for bullet in about:
            if isinstance(bullet, str) and bullet.strip():
                parts.append(f"  <li>{_escape_html(bullet.strip())}</li>")
        parts.append("</ul>")

    if overview:
        if isinstance(overview, str):
            try:
                overview = json.loads(overview)
            except (json.JSONDecodeError, TypeError):
                overview = []

        if overview:
            parts.append("<h3>Product Details</h3>")
            parts.append("<table>")
            for item in overview:
                if isinstance(item, dict):
                    for key, val in item.items():
                        parts.append(f"  <tr><td><strong>{_escape_html(str(key))}</strong></td><td>{_escape_html(str(val))}</td></tr>")
                elif isinstance(item, str):
                    parts.append(f"  <tr><td colspan='2'>{_escape_html(item)}</td></tr>")
            parts.append("</table>")

    return "\n".join(parts)


def _escape_html(text: str) -> str:
    """Basic HTML escaping."""
    return (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def _build_variants(options: dict, base_price: float, asin: str) -> tuple[list, list]:
    """Build Shopify options and variants from Amazon option data.

    Returns:
        (options_list, variants_list) for the Shopify product
    """
    if not options or not isinstance(options, dict):
        # Single variant (no options)
        return [], [{
            "price": str(base_price),
            "sku": asin,
            "inventory_management": None,  # No inventory tracking for dropship
            "fulfillment_service": "manual",
            "requires_shipping": True,
            "taxable": True,
        }]

    # Build options from Amazon data (e.g., {"Color": ["Red", "Blue"], "Size": ["S", "M", "L"]})
    shopify_options = []
    option_values = {}

    for i, (name, values) in enumerate(list(options.items())[:3]):  # Shopify max 3 options
        if isinstance(values, list):
            shopify_options.append({"name": name, "values": values[:100]})
            option_values[f"option{i+1}"] = values
        elif isinstance(values, str):
            shopify_options.append({"name": name, "values": [values]})
            option_values[f"option{i+1}"] = [values]

    # Build variant combinations (cap at 100 for Shopify limit)
    variants = []
    if len(option_values) == 1:
        for val in list(option_values.values())[0][:100]:
            variants.append({
                "option1": val,
                "price": str(base_price),
                "sku": f"{asin}-{_slugify(val)}",
                "inventory_management": None,
                "requires_shipping": True,
                "taxable": True,
            })
    elif len(option_values) >= 2:
        keys = list(option_values.keys())
        for v1 in option_values[keys[0]][:10]:
            for v2 in option_values[keys[1]][:10]:
                if len(variants) >= 100:
                    break
                variant = {
                    "option1": v1,
                    "option2": v2,
                    "price": str(base_price),
                    "sku": f"{asin}-{_slugify(v1)}-{_slugify(v2)}",
                    "inventory_management": None,
                    "requires_shipping": True,
                    "taxable": True,
                }
                if len(option_values) >= 3 and keys[2] in option_values:
                    for v3 in option_values[keys[2]][:10]:
                        if len(variants) >= 100:
                            break
                        v = dict(variant)
                        v["option3"] = v3
                        v["sku"] = f"{asin}-{_slugify(v1)}-{_slugify(v2)}-{_slugify(v3)}"
                        variants.append(v)
                else:
                    variants.append(variant)

    if not variants:
        variants = [{
            "price": str(base_price),
            "sku": asin,
            "inventory_management": None,
            "requires_shipping": True,
            "taxable": True,
        }]

    return shopify_options, variants[:100]


def _slugify(text: str) -> str:
    """Simple slugify for SKU suffix."""
    return re.sub(r'[^a-zA-Z0-9]', '', text)[:10].lower()
