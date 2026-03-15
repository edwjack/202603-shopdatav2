---
id: sqlcl-no-native-binds
name: sqlcl-no-native-binds
description: "SQLcl -S (silent) mode via subprocess does not support parameterized queries. All bind variables must be substituted as strings before sending SQL. This creates an inherent SQL injection surface that requires defense-in-depth sanitization."
triggers:
  - "SQLcl bind variable"
  - "sql -S bind"
  - "sqlcl parameterized"
  - "sanitizeBindValue"
  - "SQL injection subprocess"
---

# SQLcl Silent Mode Has No Native Bind Variable Support

## The Insight

When using SQLcl as a subprocess (`sql -name <conn> -S`) for database access, there is no mechanism to pass bind variables separately from the SQL text. Unlike oracledb's `conn.execute(sql, binds)` or JDBC's PreparedStatement, SQLcl's stdin-based interface accepts raw SQL text only. This means ALL parameterization must happen via string substitution before the SQL reaches SQLcl — creating an inherent injection surface that cannot be eliminated, only mitigated.

## Why This Matters

If you assume SQLcl works like a database driver with bind support, you'll write code like:
```typescript
const sql = `SELECT * FROM users WHERE id = :id`;
// Expecting SQLcl to handle :id as a bind parameter — IT WON'T
```

SQLcl will treat `:id` as a literal string in the SQL, causing either a syntax error or unexpected behavior. You must substitute the value yourself:
```typescript
resolvedSql = sql.replace(':id', sanitizeBindValue(id));
```

This string substitution approach means SQL injection is always a risk, regardless of how careful you are. The mitigation strategy must be **defense-in-depth**:

1. **Type-specific sanitization** — numerics via `Number.isFinite()`, strings via multi-layer escaping
2. **Input validation at API boundary** — allowlist enum values, validate types before they reach the DB layer
3. **Principle of least privilege** — DB user should have minimal permissions

## Recognition Pattern

- Using SQLcl subprocess for any database access (not just this project)
- Migrating from oracledb driver (which has native binds) to SQLcl subprocess
- Seeing `:bindName` placeholders in SQL used with SQLcl
- Building any `execFile`/`spawn`-based database interface

## The Approach

**Accept that string substitution is inherently less safe than parameterized queries.** Then compensate:

1. **Validate at the boundary**: Every API route that accepts user input must validate BEFORE calling the DB layer. Use allowlists for enum fields (status values, types), strict type checks for IDs, length limits for free text.

2. **Sanitize per-type in the DB layer**: The `sanitizeBindValue()` function is your last line of defense. It must handle:
   - Numerics: `Number.isFinite()` check, reject NaN/Infinity
   - Strings: Remove null bytes, escape backslashes, escape single quotes
   - Null/undefined: Convert to SQL `NULL`

3. **Don't rely on sanitization alone**: The API validation layer should catch most attacks before they reach sanitization. Sanitization is the safety net, not the primary defense.

## Example

```typescript
// Defense-in-depth: API route validates BEFORE DB call
if (!isValidTaskStatus(body.status)) {
  return Response.json({ error: 'Invalid status' }, { status: 400 });
}
// DB layer sanitizes as second defense
function sanitizeBindValue(value: unknown): string {
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) throw new Error('Invalid numeric');
    return String(value);
  }
  if (typeof value === 'string') {
    return `'${value.replace(/\0/g, '').replace(/\\/g, '\\\\').replace(/'/g, "''")}'`;
  }
  if (value === null || value === undefined) return 'NULL';
  return String(value);
}
```
