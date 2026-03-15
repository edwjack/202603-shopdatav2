"""Parse Amazon product overview/attributes from detail page HTML."""
from selectolax.parser import HTMLParser


def parse_overview(html: str) -> list[dict]:
    """Extract product overview attributes (Color, Size, Material, etc.).

    Returns list of dicts with keys: name, value
    """
    tree = HTMLParser(html)
    attributes = []

    # Product Overview table (#productOverview_feature_div)
    overview_div = tree.css_first("#productOverview_feature_div")
    if overview_div:
        rows = overview_div.css("tr")
        for row in rows:
            label = row.css_first("td.a-span3, th")
            value = row.css_first("td.a-span9, td:last-child")
            if label and value:
                attributes.append({
                    "name": label.text(strip=True),
                    "value": value.text(strip=True),
                })

    # Technical Details table (#productDetails_techSpec_section_1)
    if not attributes:
        tech_table = tree.css_first("#productDetails_techSpec_section_1")
        if tech_table:
            rows = tech_table.css("tr")
            for row in rows:
                th = row.css_first("th")
                td = row.css_first("td")
                if th and td:
                    attributes.append({
                        "name": th.text(strip=True),
                        "value": td.text(strip=True),
                    })

    return attributes
