---
id: sqlcl-cloudconfig-silent-mode
name: sqlcl-cloudconfig-silent-mode
description: "sql -cloudconfig wallet.zip user/pass@tns -S" fails with "connect request not recognized" in Node.js execSync subprocess. Use "sql /nolog -S" with "set cloudconfig" + "connect" as SQL input instead.
source: session-20260216-hkt-schema
triggers:
  - "connect request was not recognized"
  - "sql -cloudconfig"
  - "execSync sql"
  - "sqlcl subprocess wallet"
  - "HKT schema creation failed"
quality: verified-production
---

# SQLcl -cloudconfig Flag Fails with -S Silent Mode in execSync

## The Insight

SQLcl's `-cloudconfig` command-line flag is incompatible with `-S` (silent) mode when invoked via Node.js `execSync` subprocess. The connection string parsing breaks, producing "The connect request was not recognized". The fix: use `/nolog -S` and feed `set cloudconfig` + `connect` as SQL input.

## Why This Matters

Schema creation via `execSync` silently fails, returning a misleading error. The instance provisioning proceeds without a DB schema, and the team gets an instance with no database access. This happened in production during R1G3 instance creation.

## Recognition Pattern

- Using `execSync('sql -cloudconfig wallet.zip user/pass@tns -S', { input: sql })`
- Error: "The connect request was not recognized: please type HELP CONNECT"
- Any SQLcl subprocess that needs wallet-based ADB connection in silent mode

## The Approach

Never combine `-cloudconfig` with connection credentials on the command line. Instead:

1. Start SQLcl with `/nolog -S` (no login, silent)
2. Use `set cloudconfig /path/to/wallet.zip` as first SQL input line
3. Use `connect user/pass@tns_service` as second line
4. Then your actual SQL statements

## Example

```typescript
// BAD - fails with "connect request not recognized"
execSync(
  `sql -cloudconfig ${walletPath} ${adminUser}/${adminPass}@${tns} -S`,
  { input: sql, encoding: 'utf-8', timeout: 30000 }
);

// GOOD - works correctly
const fullSql = `set cloudconfig ${walletPath}\nconnect ${adminUser}/${adminPass}@${tns}\n${sql}`;
execSync(
  'sql /nolog -S',
  { input: fullSql, encoding: 'utf-8', timeout: 30000 }
);
```

Note: Interactive `sql -cloudconfig wallet.zip user/pass@tns` works fine in a terminal. The issue is specific to `-S` mode with piped input via subprocess.
