"""Parse Amazon product images from detail page HTML."""
import re
import json
from typing import Optional


def parse_images(html: str) -> list[dict]:
    """Extract product images at multiple resolutions from Amazon HTML.

    Returns list of dicts with keys: hiRes, large, thumb, variant
    """
    images = []

    # Try extracting from colorImages JS variable
    match = re.search(r"'colorImages'\s*:\s*\{[^}]*'initial'\s*:\s*(\[.*?\])\s*\}", html, re.DOTALL)
    if match:
        try:
            raw = match.group(1)
            raw = raw.replace("'", '"')
            data = json.loads(raw)
            for item in data:
                images.append({
                    "hiRes": item.get("hiRes"),
                    "large": item.get("large"),
                    "thumb": item.get("thumb"),
                    "variant": item.get("variant", "MAIN"),
                })
        except (json.JSONDecodeError, KeyError):
            pass

    # Fallback: extract from imageGalleryData
    if not images:
        match = re.search(r"ImageBlockATF.*?data\s*=\s*(\[.*?\]);", html, re.DOTALL)
        if match:
            try:
                data = json.loads(match.group(1))
                for item in data:
                    images.append({
                        "hiRes": item.get("hiRes"),
                        "large": item.get("mainUrl"),
                        "thumb": item.get("thumbUrl"),
                        "variant": "MAIN",
                    })
            except (json.JSONDecodeError, KeyError):
                pass

    return images


def get_main_image(images: list[dict]) -> Optional[str]:
    """Get the best resolution main image URL."""
    for img in images:
        if img.get("variant") == "MAIN":
            return img.get("hiRes") or img.get("large")
    if images:
        return images[0].get("hiRes") or images[0].get("large")
    return None
