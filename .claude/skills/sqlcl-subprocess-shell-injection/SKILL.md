---
id: sqlcl-subprocess-shell-injection
name: sqlcl-subprocess-shell-injection
description: Using echo pipe to feed SQL to SQLcl subprocess creates shell injection — use execSync input option instead
source: session-2026-02-02-tripapproval-code-review
triggers:
  - "execSync"
  - "echo pipe"
  - "sqlcl subprocess"
  - "shell injection"
  - "oracle.ts"
  - "command injection"
quality: high
---

# SQLcl Subprocess Shell Injection via Echo Pipe

## The Insight

When using Node.js `execSync` to run SQLcl as a subprocess, piping SQL via `echo "${escaped}"` creates a shell injection surface. Even with double-quote escaping (`replace(/"/g, '\\"')`), attackers can break out via backticks, `$()`, or other shell metacharacters. The `execSync` `input` option bypasses the shell entirely for the SQL payload.

## Why This Matters

The SQLcl subprocess pattern (used when node-oracledb thin driver can't use wallet SSO) inherently lacks parameterized queries. Combined with echo-pipe shell injection, this creates a double injection surface: SQL injection AND shell command injection. Fixing the shell injection is the higher priority since it allows arbitrary OS command execution.

## Recognition Pattern

- Any code using `execSync('echo "..." | sqlcl ...')`
- String interpolation of SQL into shell commands
- SQLcl subprocess adapter pattern in Node.js

## The Approach

**Never pass SQL through the shell.** Use the `input` option of `execSync` which writes directly to stdin without shell interpretation:

```typescript
// VULNERABLE: SQL goes through shell interpretation
const escaped = fullCommand.replace(/"/g, '\\"');
execSync(`echo "${escaped}" | sqlcl -S ...`, { encoding: 'utf8' });

// SAFE: SQL goes directly to stdin, no shell interpretation
execSync(`sqlcl -S ...`, { input: fullCommand, encoding: 'utf8' });
```

This eliminates shell metacharacter interpretation (`$()`, backticks, `&&`, `||`, `;`) while keeping the SQLcl subprocess pattern intact.

## Example

```typescript
// db/oracle.ts — executeSQL function
export async function executeSQL(sql: string): Promise<any[]> {
  const connectStr = `${user}/${password}@${connStr}`;
  const fullCommand = `SET SQLFORMAT CSV\n${sql};`;

  const result = execSync(
    `${SQLCL_PATH} -S -cloudconfig ${WALLET_PATH} ${connectStr}`,
    { input: fullCommand, encoding: 'utf8', timeout: 30000, maxBuffer: 10 * 1024 * 1024 }
  );
  return parseCSV(result.trim());
}
```
