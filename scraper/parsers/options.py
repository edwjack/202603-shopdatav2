"""Parse Amazon product options/variants from detail page HTML."""
import re
import json


def parse_options(html: str) -> dict:
    """Extract product variation options (size, color, style, etc.).

    Returns dict with dimension names as keys and list of values.
    Example: {"Color": ["Red", "Blue"], "Size": ["Small", "Large"]}
    """
    options = {}

    # Try twisterModel JS variable
    match = re.search(r"twisterModel\s*=\s*(\{.*?\});", html, re.DOTALL)
    if match:
        try:
            data = json.loads(match.group(1))
            dimensions = data.get("dimensions", [])
            for dim in dimensions:
                name = dim.get("name", "")
                values = [v.get("value", "") for v in dim.get("values", [])]
                if name and values:
                    options[name] = values
        except (json.JSONDecodeError, KeyError):
            pass

    # Fallback: parse from variation dropdown
    if not options:
        match = re.search(r'"variationValues"\s*:\s*(\{[^}]+\})', html)
        if match:
            try:
                data = json.loads(match.group(1))
                for key, values in data.items():
                    options[key] = values
            except (json.JSONDecodeError, KeyError):
                pass

    return options
