---
name: mcp-sqlcl-wallet-cache-renewal
description: MCP SQLcl saved connections cache wallet files in ~/.dbtools/connections/<hash>/ — replacing the wallet zip alone does NOT fix ORA-29024/ORA-17002 cert errors. Must also update cached files in each connection directory.
---

# MCP SQLcl Wallet Cache Renewal

## Problem

When an Oracle ADB wallet expires (ORA-29024 certificate validation failure / ORA-17002 PKIX path building failed), replacing the wallet zip file (e.g., `/home/opc/Wallet_JK26aiAppCT.zip`) and restarting the MCP oracle server is NOT sufficient.

MCP SQLcl's `conn -save` command extracts wallet files into `~/.dbtools/connections/<hash>/` at save time. These cached copies are what the connection actually uses, not the original zip.

## Symptom

After wallet zip replacement + MCP restart:
```
ORA-17002: I/O error: IO Error PKIX path building failed:
sun.security.provider.certpath.SunCertPathBuilderException:
unable to find valid certification path to requested target
```

## Fix

1. Identify all saved connection directories:
   ```bash
   ls ~/.dbtools/connections/
   ```

2. For each directory that contains wallet files (cwallet.sso exists):
   ```bash
   for dir in ~/.dbtools/connections/*/; do
     if [ -f "$dir/cwallet.sso" ]; then
       unzip -o /home/opc/Wallet_JK26aiAppCT.zip -x README -d "$dir"
     fi
   done
   ```

3. Restart MCP oracle server (`/mcp` → restart oracle)

4. Test connection:
   ```
   mcp__oracle__connect(connection_name="<name>")
   ```

## Key Insight

- `conn -save` extracts wallet at save time — it does NOT reference the original zip at runtime
- All connections sharing the same ADB wallet need their cached copies updated
- The `-x README` flag avoids overwriting the connection's own README/credentials
