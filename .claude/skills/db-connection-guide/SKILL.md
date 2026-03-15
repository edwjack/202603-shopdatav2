---
name: db-connection-guide
description: Oracle ADB connection guide for MCP SQLcl saved connections
triggers:
  - "oracle connection"
  - "db connection"
  - "sqlcl connection"
  - "saved connection"
  - "mcp oracle"
---

# Oracle ADB Saved Connection Pattern for MCP SQLcl

## Overview

This skill documents the end-to-end pattern for managing Oracle Autonomous Database connections using SQLcl saved connections and the MCP Oracle server.

## Creating Saved Connections

### Initial Connection and Save

```bash
# Connect using cloudconfig wallet (zip file, no extract needed)
sql -cloudconfig /path/to/Wallet_Name.zip username/password@SERVICE_NAME

# Once connected, save the connection
SQL> conn -save <ConnectionName> -savepwd
```

**Key Points:**
- Wallet zip file is used directly via `-cloudconfig` (no extraction required)
- `-savepwd` stores credentials securely in SQLcl config
- Connection names are case-sensitive
- Saved connections are stored per-user in `~/.dbtools/connections.json`

### Verify Saved Connection

```bash
# List all saved connections
sql /nolog
SQL> conn -list

# Or use MCP tool
mcp__oracle__list-connections(show_details=true)
```

## Using Saved Connections

### Method 1: SQLcl Command Line

```bash
# Start SQLcl with saved connection
sql -name <ConnectionName>

# Or connect after starting SQLcl
sql /nolog
SQL> connect -name <ConnectionName>
```

### Method 2: MCP Oracle Server

```typescript
// 1. List available connections
mcp__oracle__list-connections()

// 2. Connect to saved connection
mcp__oracle__connect(connection_name="<ConnectionName>")

// 3. Execute SQL
mcp__oracle__run-sql(sql="SELECT * FROM table_name")

// 4. Execute SQLcl commands
mcp__oracle__run-sqlcl(sqlcl="desc table_name")
```

## MCP Oracle Server Connection Flow

### Standard Workflow

```
1. mcp__oracle__list-connections()
   → Get available connection names

2. mcp__oracle__connect(connection_name="<ConnectionName>")
   → Establish session

3. mcp__oracle__run-sql(sql="...")
   → Execute queries

4. mcp__oracle__schema-information()
   → Get metadata about current schema
```

### Reconnection Flow (After Session Loss)

```
1. Try: mcp__oracle__connect(connection_name="<ConnectionName>")

2. If fails with ORA-17008: Try run-sqlcl approach:
   mcp__oracle__run-sqlcl(sqlcl="connect -name <ConnectionName>")

3. If still fails: Alert user to restart MCP oracle server
   "MCP oracle server needs restart. Please restart the MCP server."
```

## Troubleshooting

### ORA-17008: Closed Connection

**Symptom:** Connection works initially but fails later with "ORA-17008: Closed connection"

**Cause:** MCP SQLcl session timeout or network interruption

**Solution:**
1. Attempt reconnect with `mcp__oracle__connect`
2. If failed, use `mcp__oracle__run-sqlcl(sqlcl="connect -name <ConnectionName>")`
3. Last resort: Request MCP server restart from user

### Connection Not Found

**Symptom:** "Connection name not found" error

**Cause:**
- Case mismatch (connection names are case-sensitive)
- Connection not saved in current user's config
- SQLcl config file corrupted

**Solution:**
```bash
# List all saved connections to verify exact name
sql /nolog
SQL> conn -list

# Re-save connection if needed
sql -cloudconfig /path/to/wallet.zip user/pass@service
SQL> conn -save <ConnectionName> -savepwd
```

## Best Practices

### 1. Output Formatting for Parsing

```sql
-- CSV format for clean parsing (NOT SET MARKUP CSV ON)
SET SQLFORMAT CSV

-- Turn off feedback for clean output
SET FEEDBACK OFF

-- Suppress banner
SET HEADING OFF

-- Example query with clean output
SET SQLFORMAT CSV
SET FEEDBACK OFF
SELECT column1, column2 FROM table_name;
```

**Critical:** `SET MARKUP CSV ON` does NOT produce CSV format. Use `SET SQLFORMAT CSV` instead.

### 2. Transaction Management

```sql
-- PL/SQL blocks should include exception handling for atomic operations
BEGIN
  INSERT INTO table_name VALUES (...);
  UPDATE other_table SET ...;
  COMMIT;
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
END;
/
```

**Important:** MCP SQLcl auto-commits each statement. Transaction rollback testing is not possible via MCP tools.

### 3. Connection Naming Convention

```
<ProjectName><Environment>
Examples:
- ControlTowerDev
- ControlTowerProd
- ADB26aiV3
```

### 4. Schema Per Project

```sql
-- Create dedicated schema for each project
CREATE USER project_schema IDENTIFIED BY password;
GRANT CONNECT, RESOURCE TO project_schema;
ALTER USER project_schema QUOTA UNLIMITED ON DATA;

-- Save connection for the project schema
sql -cloudconfig /path/to/wallet.zip project_schema/password@SERVICE
SQL> conn -save ProjectSchemaConn -savepwd
```

## Python Integration Pattern

### Using SQLcl Subprocess with Saved Connection

```python
import subprocess
import os

def run_sqlcl_query(connection_name: str, sql: str) -> str:
    """
    Execute SQL using SQLcl saved connection via subprocess.

    Args:
        connection_name: Saved connection name (e.g., 'ADB26aiV3')
        sql: SQL query or command to execute

    Returns:
        Query output as string
    """
    # Build SQLcl command
    cmd = [
        'sql',
        '-name', connection_name,
        '-S',  # Silent mode
    ]

    # Prepare SQL with formatting
    full_sql = f"""
    SET SQLFORMAT CSV
    SET FEEDBACK OFF
    SET HEADING ON
    {sql}
    exit;
    """

    # Execute
    result = subprocess.run(
        cmd,
        input=full_sql,
        text=True,
        capture_output=True,
        timeout=30
    )

    if result.returncode != 0:
        raise RuntimeError(f"SQLcl error: {result.stderr}")

    return result.stdout

# Example usage
output = run_sqlcl_query(
    connection_name='ADB26aiV3',
    sql='SELECT table_name FROM user_tables'
)
print(output)
```

**Advantages:**
- No password management needed (uses saved connection)
- Clean CSV output for parsing
- Works in E2E tests and automation
- No need for Python oracledb driver installation

### Using Python oracledb Driver

```python
import oracledb

# Requires extracted wallet
connection = oracledb.connect(
    user='username',
    password='password',
    dsn='SERVICE_NAME',
    config_dir='/path/to/extracted/wallet',
    wallet_location='/path/to/extracted/wallet',
    wallet_password=None  # If wallet has password
)

cursor = connection.cursor()
cursor.execute("SELECT * FROM table_name")
rows = cursor.fetchall()
```

**When to use:**
- Need prepared statements
- Need explicit transaction control
- Need cursor-based iteration
- Building Python service with persistent connections

## Common Patterns

### Pattern 1: Quick Schema Inspection

```bash
# Via MCP
mcp__oracle__connect(connection_name="ADB26aiV3")
mcp__oracle__schema-information()
```

### Pattern 2: DDL Execution (User Confirmation Required)

```bash
# Always confirm with user before DDL
mcp__oracle__run-sqlcl(sqlcl="CREATE TABLE test_table (id NUMBER)")
```

### Pattern 3: CSV Data Export

```sql
SET SQLFORMAT CSV
SET FEEDBACK OFF
SET PAGESIZE 0
SELECT * FROM large_table;
```

### Pattern 4: Automated Testing with Saved Connection

```python
# E2E test using SQLcl subprocess
def test_database_connection():
    result = subprocess.run(
        ['sql', '-name', 'TestConnection', '-S'],
        input="SELECT 'OK' FROM dual;\nexit;",
        text=True,
        capture_output=True
    )
    assert 'OK' in result.stdout
```

## Environment Variables

```bash
# Oracle Admin password (for schema creation)
export ORACLE_ADMIN_PASS='your_password'

# SQLcl custom settings
export SQLPATH=/path/to/sql/scripts
export TNS_ADMIN=/path/to/wallet  # Only if using extracted wallet
```

## References

- SQLcl User Guide: https://docs.oracle.com/en/database/oracle/sql-developer-command-line/
- Oracle ADB Documentation: https://docs.oracle.com/en/cloud/paas/autonomous-database/
- MCP Oracle Server: Custom implementation wrapping SQLcl `-mcp` mode

## Learnings and Gotchas

1. **CSV Format:** `SET MARKUP CSV ON` does NOT work. Use `SET SQLFORMAT CSV`.
2. **Wallet Files:** Use zip directly with `-cloudconfig`. No extraction needed for SQLcl.
3. **Auto-commit:** MCP SQLcl auto-commits each statement. No rollback testing via MCP.
4. **PL/SQL Blocks:** Must end with `/` on new line. Include exception handling for atomicity.
5. **Connection Names:** Case-sensitive. Verify with `conn -list` before use.
6. **Session Timeout:** ORA-17008 indicates session lost. Reconnect using `connect -name`.
7. **Password Management:** `-savepwd` encrypts passwords. No env vars needed for saved connections.
8. **Service Names:** HIGH/MEDIUM/LOW service names affect connection priority and resource allocation.

## Oracle RAW Hex Comparison

### The Insight

Oracle `RAW(16)` columns store binary data. When your application generates UUIDs as 32-character hex strings (e.g., `'A1B2C3D4E5F6...'`), Oracle does NOT automatically convert the hex string to RAW for comparison. The query silently returns zero rows instead of throwing an error. This is the most dangerous kind of bug: it looks like "no data" rather than "wrong query".

The fix requires two directions:
- **Writing/Filtering**: Wrap hex string params with `HEXTORAW(:param)` in WHERE/INSERT
- **Reading**: Wrap RAW columns with `RAWTOHEX(column)` in SELECT to get hex strings back

### Why This Matters

Without `HEXTORAW`, a query like `WHERE property_id = :propertyId` silently returns empty when `property_id` is `RAW(16)` and `:propertyId` is a hex string like `'A1B2C3D4...'`. Oracle's implicit type coercion behavior for RAW is inconsistent across versions and NLS settings — sometimes it works, sometimes it doesn't. The explicit conversion is the only reliable approach.

This caused bugs across 3 route files (properties.ts, bookings.ts, reviews.ts) in the HomeFind project. Each file had 2-6 queries that needed fixing. The pattern is especially insidious because:
1. INSERT works fine (Oracle can accept hex strings for RAW columns in some contexts)
2. SELECT with WHERE fails silently (returns 0 rows, no error)
3. Ownership checks fail (comparing `RAWTOHEX(landlord_id)` output against hex userId)

### Recognition Pattern

- Oracle schema has `RAW(16)` or `RAW(32)` columns for UUIDs/IDs
- Application generates hex string IDs (e.g., `crypto.randomBytes(16).toString('hex')`)
- Queries return zero rows when data clearly exists
- INSERT works but subsequent SELECT by ID fails
- Ownership checks (`property.LANDLORD_ID !== userId`) always fail

### The Approach

**Audit every query touching RAW columns. Apply these rules systematically:**

1. **WHERE clauses**: Always `HEXTORAW(:param)` when filtering by RAW column
   ```sql
   -- WRONG: silent empty result
   WHERE property_id = :propertyId

   -- RIGHT: explicit conversion
   WHERE property_id = HEXTORAW(:propertyId)
   ```

2. **SELECT output**: Use `RAWTOHEX(column)` when you need the hex string in application code
   ```sql
   -- WRONG: returns binary buffer, comparison with hex string fails
   SELECT landlord_id FROM properties WHERE id = HEXTORAW(:id)

   -- RIGHT: returns hex string, comparable with app-side hex IDs
   SELECT RAWTOHEX(landlord_id) as LANDLORD_ID FROM properties WHERE id = HEXTORAW(:id)
   ```

3. **INSERT**: Hex strings usually work for RAW columns, but `HEXTORAW()` is still safer
   ```sql
   INSERT INTO properties (id) VALUES (HEXTORAW(:id))
   ```

4. **Systematic grep**: After fixing one file, grep ALL route files for `:paramName` patterns used against RAW columns. The bug tends to appear in some queries but not others within the same file.

### Example

```typescript
// BEFORE (silently broken — returns 0 rows):
const reviews = await executeQuery(
  `SELECT * FROM reviews WHERE property_id = :propertyId`,
  { propertyId: hexId }
);

// AFTER (works correctly):
const reviews = await executeQuery(
  `SELECT * FROM reviews WHERE property_id = HEXTORAW(:propertyId)`,
  { propertyId: hexId }
);

// For ownership checks — need RAWTOHEX on the column side:
const property = await executeQuery(
  `SELECT RAWTOHEX(landlord_id) as LANDLORD_ID FROM properties WHERE id = HEXTORAW(:propertyId)`,
  { propertyId: hexId }
);
if (property.LANDLORD_ID !== userId) {
  return res.status(403).json({ error: 'Not authorized' });
}
```


## Oracle RAW Hex Comparison
