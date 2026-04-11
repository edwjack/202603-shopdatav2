---
name: shopify-sync-check
description: Verify local DB and Shopify draft articles are in sync — detect orphans and stale syncs
triggers:
  - shopify sync
  - shopify check
  - publish check
  - shopify health
---
# Shopify Sync Check — DB/Shopify Reconciliation

Verify that local blog records and Shopify draft articles are synchronized.

## Arguments
- Shop name (optional, default: all active shops)

## Instructions

### 1. Connect to Oracle DB
```
mcp__oracle__connect(connection_name="202603-blogautov2")
```

### 2. Published Blogs Without Shopify ID (Orphans)
```sql
SELECT s.NAME as shop_name, b.ID, b.TITLE, b.STATUS, b.PUBLISHED_AT
FROM PROJBLOG2.BLOGS b
JOIN PROJBLOG2.SHOPS s ON b.SHOP_ID = s.ID
WHERE b.STATUS = 'published'
AND b.SHOPIFY_ARTICLE_ID IS NULL
ORDER BY b.PUBLISHED_AT DESC
```

### 3. Approved But Not Published (Stuck Pipeline)
```sql
SELECT s.NAME, b.ID, b.TITLE, b.QUALITY_TIER, b.CREATED_AT,
       ROUND((SYSDATE - CAST(b.CREATED_AT AS DATE)) * 24, 1) as hours_waiting
FROM PROJBLOG2.BLOGS b
JOIN PROJBLOG2.SHOPS s ON b.SHOP_ID = s.ID
WHERE b.STATUS = 'approved'
AND (SYSDATE - CAST(b.CREATED_AT AS DATE)) * 24 > 1
ORDER BY b.CREATED_AT ASC
```

### 4. Publish Success Summary
```sql
SELECT s.NAME,
       COUNT(CASE WHEN b.STATUS = 'published' AND b.SHOPIFY_ARTICLE_ID IS NOT NULL THEN 1 END) as synced,
       COUNT(CASE WHEN b.STATUS = 'published' AND b.SHOPIFY_ARTICLE_ID IS NULL THEN 1 END) as orphaned,
       COUNT(CASE WHEN b.STATUS = 'approved' THEN 1 END) as pending_publish
FROM PROJBLOG2.BLOGS b
JOIN PROJBLOG2.SHOPS s ON b.SHOP_ID = s.ID
WHERE s.STATUS = 'active'
GROUP BY s.NAME
ORDER BY s.NAME
```

### 5. Product Sync Freshness
```sql
SELECT s.NAME, s.STATUS,
       COUNT(p.ID) as product_count,
       MAX(p.LAST_SYNCED_AT) as last_sync,
       CASE
         WHEN MAX(p.LAST_SYNCED_AT) IS NULL THEN 'NEVER'
         WHEN (SYSDATE - CAST(MAX(p.LAST_SYNCED_AT) AS DATE)) > 30 THEN 'CRITICAL (>30 days)'
         WHEN (SYSDATE - CAST(MAX(p.LAST_SYNCED_AT) AS DATE)) > 7 THEN 'WARNING (>7 days)'
         ELSE 'OK'
       END as sync_status
FROM PROJBLOG2.SHOPS s
LEFT JOIN PROJBLOG2.PRODUCTS p ON p.SHOP_ID = s.ID
WHERE s.STATUS = 'active'
GROUP BY s.NAME, s.STATUS
ORDER BY s.NAME
```

### 6. Access Token Health
```sql
SELECT NAME, STATUS,
       CASE WHEN ACCESS_TOKEN IS NOT NULL THEN 'Present' ELSE 'MISSING' END as token_status
FROM PROJBLOG2.SHOPS
WHERE STATUS = 'active'
```

### 7. Output Format
```
## Shopify Sync Report

### Sync Summary
| Shop | Synced | Orphaned | Pending | Status |
|------|--------|----------|---------|--------|
| ... | 45 | 0 | 2 | OK |

### Orphaned Records (published locally, no Shopify ID)
[list if any, with recommended action]

### Stuck Pipeline (approved > 1 hour, not published)
[list if any]

### Product Sync Freshness
| Shop | Products | Last Sync | Status |
|------|----------|-----------|--------|
| ... | 50 | 2 days ago | OK |

### Access Tokens
[status per shop]

### Overall: IN SYNC / DRIFT DETECTED / CRITICAL
```
