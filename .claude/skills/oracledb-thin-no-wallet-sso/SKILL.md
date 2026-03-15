---
id: oracledb-thin-no-wallet-sso
name: oracledb-thin-no-wallet-sso
description: "The Node.js oracledb thin driver requires explicit username/password. cwallet.sso auto-login only works with SQLcl/JDBC (thick clients). Use SQLcl subprocess as alternative."
triggers:
  - "NJS-101"
  - "no credentials specified"
  - "oracledb thin wallet"
  - "cwallet.sso node"
  - "wallet auto-login node.js"
---

# Oracle node-oracledb Thin Driver Does Not Support Wallet SSO

## The Insight

Oracle's `cwallet.sso` (auto-login wallet) authentication works with Java-based clients (SQLcl, JDBC, SQL Developer) but **NOT** with node-oracledb in thin mode. The thin driver always requires explicit `user` + `password` parameters. Omitting password results in `NJS-101: no credentials specified`.

This is a fundamental architectural difference: thick mode (via Oracle Client libraries) delegates auth to the native Oracle client which reads the wallet. Thin mode implements its own TLS stack and does not parse SSO wallet credentials.

## Why This Matters

When you have an MCP SQLcl saved connection with `-savepwd` that works perfectly, you might assume the same wallet directory can authenticate a Node.js app. It cannot. You'll waste time configuring `configDir` and `walletLocation` only to hit `NJS-101`.

## Recognition Pattern

- Building a Node.js/Next.js app that needs Oracle ADB access
- Have a working SQLcl saved connection or wallet with `cwallet.sso`
- Trying to avoid storing passwords in `.env` files
- See `NJS-101: no credentials specified` despite valid wallet path

## The Approach

**Decision tree:**

1. **Need connection pooling + performance?** → Use oracledb thin driver with explicit password (env var, secrets manager, or vault)
2. **Can tolerate subprocess overhead?** → Use `sql -name <ConnectionName> -S` subprocess with `SET SQLFORMAT JSON-FORMATTED` for JSON output
3. **Building a CLI/script (not a server)?** → SQLcl subprocess is the better choice

**SQLcl subprocess pattern for Next.js API routes:**
```typescript
import { spawn } from 'child_process';

// Use spawn (async, non-blocking) instead of execSync
const proc = spawn('sql', ['-name', 'ADB26aiV3', '-S']);
proc.stdin.write(`SET SQLFORMAT JSON-FORMATTED\nSET FEEDBACK OFF\n${sql};\nexit;\n`);
proc.stdin.end();
```

## Example

```typescript
// This FAILS with NJS-101:
await oracledb.createPool({
  user: 'ADMIN',
  // password omitted — hoping wallet SSO handles it
  connectString: 'jk26aiappct_high',
  configDir: '~/.dbtools/connections/tIMHZjnGQqdoiIfFjbATyA',
  walletLocation: '~/.dbtools/connections/tIMHZjnGQqdoiIfFjbATyA',
});

// This WORKS — SQLcl reads saved credentials:
const proc = spawn('sql', ['-name', 'ADB26aiV3', '-S']);
proc.stdin.write('SELECT 1 FROM dual;\nexit;\n');
proc.stdin.end();
```
