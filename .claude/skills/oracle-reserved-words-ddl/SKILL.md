---
id: oracle-reserved-words-ddl
name: oracle-reserved-words-ddl
description: Oracle 23ai rejects reserved words as column names with ORA-03050, requiring column renames and backend SQL alignment
source: session-2026-02-02-tripapproval-ddl-rewrite
triggers:
  - "ORA-03050"
  - "invalid identifier"
  - "reserved word"
  - "column name"
  - "DATE column"
  - "SIZE column"
  - "CREATE TABLE fails"
quality: high
---

# Oracle Reserved Words Break DDL Silently

## The Insight

Oracle 23ai enforces reserved word restrictions strictly. Common English words like `DATE`, `SIZE`, `NUMBER`, `COMMENT`, `USER`, `ORDER` are reserved and CANNOT be used as bare column names. The error `ORA-03050: invalid identifier: "X" is a reserved word` only appears at CREATE TABLE time, not during development.

## Why This Matters

When backend code uses column names like `date` or `size` in SQL string interpolation, everything looks fine until you try to create the actual Oracle table. The mismatch between "works in code" and "fails in DDL" wastes significant debugging time.

## Recognition Pattern

- Writing DDL for Oracle tables where column names match common English words
- `ORA-03050` error during table creation
- Backend uses `date`, `size`, `comment`, `order`, `user`, `number` as column names

## The Approach

1. **Before writing DDL**: Cross-check every column name against Oracle reserved words
2. **Common traps**: `DATE` -> `item_date`, `SIZE` -> `file_size`, `COMMENT` -> `comments`, `ORDER` -> `sort_order`, `USER` -> `user_id`
3. **When renaming**: Update BOTH the DDL AND every backend SQL query referencing that column
4. **Alternative**: Double-quote the column name (`"DATE"`) but this forces case-sensitivity everywhere — avoid this, rename instead

## Example

```sql
-- FAILS: ORA-03050
CREATE TABLE itinerary_items (date TIMESTAMP);

-- WORKS: renamed to item_date
CREATE TABLE itinerary_items (item_date TIMESTAMP);
```

Backend fix required:
```typescript
// Before: INSERT INTO itinerary_items (date) VALUES (...)
// After:  INSERT INTO itinerary_items (item_date) VALUES (...)
```
