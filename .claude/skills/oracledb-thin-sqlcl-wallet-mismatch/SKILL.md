---
id: oracledb-thin-sqlcl-wallet-mismatch
name: oracledb-thin-sqlcl-wallet-mismatch
description: "When migrating from SQLcl subprocess to oracledb thin driver, the SQLcl saved connection may use a completely different wallet and TNS service than the project's .env wallet zip"
source: conversation
triggers:
  - "oracledb thin"
  - "ORA-01017"
  - "sqlcl to oracledb"
  - "wallet mismatch"
  - "NJS-505 bad decrypt"
  - "connection pool ORA-01017"
  - "PROJTEAMVB not found"
quality: validated
---

# SQLcl Saved Connection Wallet != Project Wallet on oracledb Thin Migration

## The Insight

SQLcl saved connections (`~/.dbtools/connections/*/`) bundle their **own wallet files** (tnsnames.ora, ewallet.p12, cwallet.sso) that may point to a completely different ADB database than the wallet zip referenced in the project's `.env`. The connection name (e.g., `202602-teamvibe`) is an abstraction layer — the actual TNS service, wallet, and even database behind it can differ from what you assume.

## Why This Matters

When migrating from SQLcl subprocess (`spawn('sql', ['-S', '/nolog'])` + `conn -name X`) to oracledb thin driver, you must match the **exact wallet + TNS + credentials** that SQLcl was using internally. Using the wrong wallet zip connects to a different database where the schema user doesn't exist, producing misleading `ORA-01017` errors.

In this project:
- `.env` had `HKT_WALLET_PATH=/home/opc/202602-teamvibe/Wallet_HKT202602.zip` → TNS: `hkt202602_high` (admin DB for remote instances)
- SQLcl `202602-teamvibe` connection used `~/.dbtools/connections/m-PJVkcDo-cayahur0Cm0w/` → TNS: `jk26aiappct_high` (app DB with PROJTEAMVB schema)
- Same ADB GUID prefix (`g2c3435895384da`) but **different databases** with different users

## Recognition Pattern

- Migrating from SQLcl subprocess to oracledb thin driver
- `ORA-01017: invalid credential or not authorized` despite correct-looking credentials
- Pool creates successfully but connections fail on auth
- Schema user doesn't exist when checked via admin (`SELECT username FROM all_users`)
- `NJS-505: bad decrypt` when using saved connection wallet (wrong PKCS12 password)

## The Approach

1. **Don't assume the .env wallet is the right one.** Inspect the actual SQLcl saved connection:
   ```bash
   cat ~/.dbtools/connections/<id>/dbtools.properties  # → connectionString, userName
   cat ~/.dbtools/connections/<id>/tnsnames.ora         # → actual TNS entries
   ```

2. **Find the correct wallet zip** for the TNS service the saved connection uses:
   ```bash
   find /home/opc -maxdepth 3 -name "*.zip" -iname "*wallet*"
   ```

3. **The PKCS12 wallet password may differ per wallet.** Each ADB wallet has its own password set at download time. The saved connection uses `cwallet.sso` (auto-login, no password — thick mode only), but oracledb thin driver requires `ewallet.p12` + correct `walletPassword`.

4. **Test credentials isolation:** Connect as `admin` first to verify wallet+TNS work, then check if the target user exists on that specific database.

## Additional Discovery: tsx watch + oracledb pool

`tsx watch` mode sends SIGTERM on file change reload, which triggers the shutdown handler calling `closeDbPool()`. The pool gets destroyed on every reload. For development with oracledb connection pools, use `tsx` (no watch) to avoid pool lifecycle disruption.

## Example

```typescript
// Correct config for this project (jk26aiappct, NOT hkt202602)
pool = await oracledb.createPool({
  user: 'PROJTEAMVB',
  password: process.env.ORACLE_PASSWORD,
  connectString: 'jk26aiappct_high',        // NOT hkt202602_high
  configDir: walletDir,                       // Wallet_JK26aiAppCT.zip extracted
  walletLocation: walletDir,
  walletPassword: 'Mcp123456789',            // NOT Mcp1234567899 (hkt wallet)
});
```

## Key Files

- `~/.dbtools/connections/m-PJVkcDo-cayahur0Cm0w/dbtools.properties` — SQLcl saved connection config
- `/home/opc/Wallet_JK26aiAppCT.zip` — correct wallet for app DB
- `/home/opc/202602-teamvibe/Wallet_HKT202602.zip` — admin DB wallet (for remote instances)
- `backend/src/config/database.ts` — oracledb pool init
- `backend/.env` — `ORACLE_WALLET_PATH`, `ORACLE_TNS_SERVICE`, `ORACLE_WALLET_PASSWORD`
