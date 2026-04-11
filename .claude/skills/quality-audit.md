---
name: quality-audit
description: Blog quality scoring distribution, trend analysis, and anomaly detection
triggers:
  - quality audit
  - blog quality
  - quality check
  - seo audit
---
# Quality Audit — Scoring Distribution & Trends

Analyze blog quality distribution, SEO score trends, and detect anomalies.

## Arguments
- Date range (optional, default: last 30 days)
- Shop name (optional, default: all)

## Instructions

### 1. Connect to Oracle DB
```
mcp__oracle__connect(connection_name="202603-blogautov2")
```

### 2. Quality Tier Distribution
```sql
SELECT s.NAME, b.QUALITY_TIER, COUNT(*) as cnt,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY s.NAME), 1) as pct
FROM PROJBLOG2.BLOGS b
JOIN PROJBLOG2.SHOPS s ON b.SHOP_ID = s.ID
WHERE b.CREATED_AT >= SYSDATE - :days
AND b.STATUS NOT IN ('draft', 'generating')
GROUP BY s.NAME, b.QUALITY_TIER
ORDER BY s.NAME, b.QUALITY_TIER
```

### 3. SEO Score Distribution
```sql
SELECT
  CASE
    WHEN SEO_SCORE >= 9 THEN 'Excellent (9-10)'
    WHEN SEO_SCORE >= 7 THEN 'Good (7-8)'
    WHEN SEO_SCORE >= 5 THEN 'Fair (5-6)'
    WHEN SEO_SCORE >= 3 THEN 'Poor (3-4)'
    ELSE 'Very Poor (0-2)'
  END as score_range,
  COUNT(*) as cnt
FROM PROJBLOG2.BLOGS
WHERE SEO_SCORE IS NOT NULL
AND CREATED_AT >= SYSDATE - :days
GROUP BY
  CASE
    WHEN SEO_SCORE >= 9 THEN 'Excellent (9-10)'
    WHEN SEO_SCORE >= 7 THEN 'Good (7-8)'
    WHEN SEO_SCORE >= 5 THEN 'Fair (5-6)'
    WHEN SEO_SCORE >= 3 THEN 'Poor (3-4)'
    ELSE 'Very Poor (0-2)'
  END
ORDER BY MIN(SEO_SCORE) DESC
```

### 4. Bottom 5 Performers
```sql
SELECT b.ID, b.TITLE, s.NAME as shop, b.SEO_SCORE, b.QUALITY_TIER,
       b.WORD_COUNT, b.CREATED_AT
FROM PROJBLOG2.BLOGS b
JOIN PROJBLOG2.SHOPS s ON b.SHOP_ID = s.ID
WHERE b.SEO_SCORE IS NOT NULL
AND b.CREATED_AT >= SYSDATE - :days
ORDER BY b.SEO_SCORE ASC
FETCH FIRST 5 ROWS ONLY
```

### 5. Dimension Breakdown (from BLOG_SCORES)
```sql
SELECT bs.DIMENSION,
       ROUND(AVG(bs.SCORE), 2) as avg_score,
       ROUND(MIN(bs.SCORE), 2) as min_score,
       ROUND(MAX(bs.SCORE), 2) as max_score
FROM PROJBLOG2.BLOG_SCORES bs
JOIN PROJBLOG2.BLOGS b ON bs.BLOG_ID = b.ID
WHERE b.CREATED_AT >= SYSDATE - :days
GROUP BY bs.DIMENSION
ORDER BY avg_score ASC
```

### 6. Dead Internal Links
```sql
SELECT bil.SOURCE_BLOG_ID, b_src.TITLE as source_title,
       bil.TARGET_BLOG_ID, b_tgt.TITLE as target_title,
       b_tgt.STATUS as target_status
FROM PROJBLOG2.BLOG_INTERNAL_LINKS bil
JOIN PROJBLOG2.BLOGS b_src ON bil.SOURCE_BLOG_ID = b_src.ID
JOIN PROJBLOG2.BLOGS b_tgt ON bil.TARGET_BLOG_ID = b_tgt.ID
WHERE b_tgt.STATUS NOT IN ('published', 'approved')
```

### 7. Weekly Trend (Last 4 Weeks)
```sql
SELECT TRUNC(b.CREATED_AT, 'IW') as week_start,
       COUNT(*) as blogs,
       ROUND(AVG(b.SEO_SCORE), 1) as avg_seo,
       ROUND(AVG(b.WORD_COUNT)) as avg_words,
       COUNT(CASE WHEN b.QUALITY_TIER = 'full' THEN 1 END) as full_tier_count
FROM PROJBLOG2.BLOGS b
WHERE b.CREATED_AT >= SYSDATE - 28
AND b.SEO_SCORE IS NOT NULL
GROUP BY TRUNC(b.CREATED_AT, 'IW')
ORDER BY week_start
```

### 8. Anomaly Detection
Flag these patterns:
- 3+ consecutive "minimal" quality blogs for any shop
- Sudden SEO score drop (>2 points week-over-week)
- Any shop with 0 "full" quality tier in last 7 days
- Average word count outside 800-1200 range for standard posts

### 9. Output Format
```
## Quality Audit Report
Period: [date range]

### Quality Tier Distribution
| Shop | Full | Partial | Minimal | Unknown |
|------|------|---------|---------|---------|
| ... | 80% | 15% | 5% | 0% |

### SEO Score Distribution
| Range | Count | % |
|-------|-------|---|
| Excellent (9-10) | 12 | 40% |
| Good (7-8) | 15 | 50% |
| Fair (5-6) | 3 | 10% |

### Bottom 5 Performers
| ID | Title | Shop | Score | Quality | Words |
|----|-------|------|-------|---------|-------|

### Weakest Dimensions
| Dimension | Avg | Min | Max |
|-----------|-----|-----|-----|

### Dead Internal Links
[list if any]

### Weekly Trend
| Week | Blogs | Avg SEO | Avg Words | Full % |
|------|-------|---------|-----------|--------|

### Anomalies
[flagged patterns]

### Overall Quality: EXCELLENT / GOOD / NEEDS ATTENTION / CRITICAL
```
