"""Parse Amazon product overview/attributes from detail page HTML."""
from scrapling.parser import Selector


def parse_overview(html: str) -> list[dict]:
    """Extract product overview attributes (Color, Size, Material, etc.).

    Returns list of dicts with keys: name, value
    """
    tree = Selector(html)
    attributes = []

    # Product Overview table (#productOverview_feature_div)
    overview_div = tree.css("#productOverview_feature_div").first
    if overview_div:
        rows = overview_div.css("tr")
        for row in rows:
            label = row.css("td.a-span3, th").first
            value = row.css("td.a-span9, td:last-child").first
            if label and value:
                attributes.append({
                    "name": label.text.strip() if label else '',
                    "value": value.text.strip() if value else '',
                })

    # Technical Details table (#productDetails_techSpec_section_1)
    if not attributes:
        tech_table = tree.css("#productDetails_techSpec_section_1").first
        if tech_table:
            rows = tech_table.css("tr")
            for row in rows:
                th = row.css("th").first
                td = row.css("td").first
                if th and td:
                    attributes.append({
                        "name": th.text.strip() if th else '',
                        "value": td.text.strip() if td else '',
                    })

    return attributes
