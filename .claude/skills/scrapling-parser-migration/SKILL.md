---
name: scrapling-parser-migration
description: selectolax HTMLParser to Scrapling Adaptor migration guide — API mapping, attribute access differences, silent data loss prevention
version: 1.0.0
triggers:
  - "selectolax.*scrapling"
  - "HTMLParser.*Adaptor"
  - "parser.*migration"
  - "attributes.*attrib"
---

# selectolax → Scrapling Adaptor Migration Guide

## API Mapping Table

| selectolax | Scrapling | Notes |
|-----------|-----------|-------|
| `from selectolax.parser import HTMLParser` | `from scrapling.parser import Selector` | or `from scrapling import Adaptor` |
| `tree = HTMLParser(html)` | `tree = Selector(html)` | html can be str or bytes |
| `tree.css('selector')` | `tree.css('selector')` | Returns Selectors (list) |
| `tree.css_first('selector')` | `tree.css('selector').first` | `.first` returns None safely |
| `el.text(strip=True)` | `el.text.strip()` | `.text` is a property in Scrapling |
| `el.attributes` | `el.attrib` | **CRITICAL: different name** |
| `el.attributes.get('key', '')` | `el.attrib.get('key', '')` | Same `.get()` pattern works |
| `el.attributes['key']` | `el.attrib['key']` | KeyError if missing |

## CRITICAL: Silent Data Loss Risk

The most dangerous change is `.attributes` → `.attrib`. If you forget this:

```python
# selectolax (works):
asin = item.attributes.get('data-asin', '')

# Scrapling — WRONG (AttributeError, but may silently return None in some contexts):
asin = item.attributes.get('data-asin', '')  # .attributes doesn't exist!

# Scrapling — CORRECT:
asin = item.attrib.get('data-asin', '')
```

**This won't raise an exception** in all cases — it may silently return empty/None, causing all products to be filtered out with no error message.

## Migration Steps (per parser file)

1. Change import: `selectolax.parser.HTMLParser` → `scrapling.Adaptor`
2. Change constructor: `HTMLParser(html)` → `Adaptor(html)`
3. Change `.css_first(sel)` → `.css(sel).first`
4. Change `.text(strip=True)` → `.text.strip()` (add `if el else ''` guard)
5. Change `.attributes` → `.attrib` (search ALL occurrences)
6. **Test**: Run both old and new parser on saved HTML fixture, compare output JSON

## Recommended Migration Order

1. **overview.py** (simplest — table parsing, no attributes.get)
2. **quantity.py** (simple + has `opt.attributes.get("value")` — tests .attrib)
3. **bestsellers.py** (complex — `item.attributes.get('data-asin')` is critical path)
4. **movers.py** (same pattern as bestsellers)

## DO NOT Migrate

- **images.py** — regex on raw HTML (no DOM parser)
- **options.py** — regex + JSON on raw HTML
- **trends.py** — pytrends API (no HTML)
- **social.py** — praw API (no HTML)
- **product_page.py** — already uses Scrapling `.css()` / `.css_first()`

## Test Pattern

```python
# Save fixture HTML before migration
with open('fixtures/bestsellers_sample.html') as f:
    html = f.read()

# Run old parser
from parsers.bestsellers_old import parse_bestsellers as old_parse
old_result = old_parse(html)

# Run new parser
from parsers.bestsellers import parse_bestsellers as new_parse
new_result = new_parse(html)

# Compare
assert old_result == new_result, f"Mismatch: {old_result} != {new_result}"
```

## Scrapling Selector Extras (not in selectolax)

```python
# CSS pseudo-elements (Scrapy-compatible)
page.css('h1::text').get()           # text node directly
page.css('a::attr(href)').getall()   # attribute values

# Regex on elements
page.css('.price').re_first(r'[\d.]+')  # regex without selecting text first

# find/find_all (BeautifulSoup-style)
page.find('div', class_='product')
page.find_all({'href*': '/dp/'})     # attribute contains
```
