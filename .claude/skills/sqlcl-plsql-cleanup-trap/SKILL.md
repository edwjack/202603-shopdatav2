---
id: sqlcl-plsql-cleanup-trap
name: sqlcl-plsql-cleanup-trap
description: PL/SQL blocks with EXCEPTION WHEN OTHERS THEN RAISE are unreliable for cleanup in SQLcl subprocess adapters — use individual DELETE+COMMIT statements instead
source: e2e-db-test-debugging-2026-02-01
triggers:
  - "ORA-00001 unique constraint"
  - "seed_meeting_data"
  - "fixture cleanup"
  - "execute_transaction cleanup"
  - "stale E2E data"
  - "PL/SQL cleanup fails silently"
  - "mcp_adapter.py"
  - "conftest.py teardown"
quality: hard-won-debugging
---

# SQLcl PL/SQL Cleanup Trap

## The Insight

When using SQLcl subprocess to execute SQL, **PL/SQL blocks with `EXCEPTION WHEN OTHERS THEN RAISE` are fundamentally incompatible with ORA-error detection in the subprocess output parser**. The RAISE re-throws the error, which appears in stdout, which the error detector picks up and throws a Python exception — even when the PL/SQL block itself executed successfully. This makes PL/SQL-based cleanup silently fail when wrapped in `try/except Exception: pass`.

The principle: **In subprocess-based DB adapters, atomic PL/SQL blocks and stdout error detection are mutually exclusive for non-error flows like DELETE cleanup.**

## Why This Matters

Symptom: `ORA-00001: unique constraint violated` on test fixture setup, even after cleanup ran. Three tests fail consistently (the 2nd, 3rd, and Nth tests that use `seed_meeting_data`), while the 1st test passes. Data accumulates across test runs.

Root cause chain:
1. `seed_meeting_data` fixture inserts `E2E-TEST-001` via `execute_transaction` (PL/SQL block with COMMIT) — works
2. Test passes
3. Teardown calls `execute_transaction` with DELETE statements in PL/SQL block
4. PL/SQL block has `EXCEPTION WHEN OTHERS THEN ROLLBACK; RAISE;`
5. Even if DELETEs succeed, any ORA message in SQLcl output triggers `_run_sqlcl` error detection
6. `_run_sqlcl` raises `OracleError`
7. `except Exception: pass` swallows it — **data NOT deleted**
8. Next test's fixture tries to INSERT same meeting_id — ORA-00001

Additionally, if MCP sessions have uncommitted transactions, concurrent SQLcl subprocesses hit `ORA-12860: deadlock detected`.

## Recognition Pattern

- E2E tests using SQLcl subprocess adapter (`mcp_adapter.py`)
- Pytest fixtures with setup/teardown that insert/delete test data
- Pattern: 1st test passes, subsequent tests with same fixture fail with ORA-00001
- `execute_transaction` used for cleanup operations
- `try/except Exception: pass` around cleanup calls

## The Approach

**Never use PL/SQL blocks (`execute_transaction`) for cleanup operations in SQLcl subprocess adapters.**

Instead, use individual DELETE+COMMIT statements — each in its own `_run_sqlcl` call:

```python
async def _cleanup_e2e_meeting(db_service, meeting_id: str) -> None:
    """Individual statements, not PL/SQL blocks."""
    for table in [
        "JK_EMAIL_LOGS",
        "JK_ACTION_ITEMS",
        "JK_TRANSCRIPTS",
        "JK_PARTICIPANTS",
        "JK_MEETINGS",
    ]:
        try:
            await db_service._run_sqlcl(
                f"DELETE FROM {table} WHERE meeting_id LIKE '{meeting_id}';\nCOMMIT;"
            )
        except Exception:
            pass
```

Why this works:
- Each DELETE is a simple SQL statement (no PL/SQL EXCEPTION handler)
- COMMIT follows immediately
- If one table's DELETE fails, others still execute
- No RAISE means no spurious ORA errors in output

**Also**: Always add pre-cleanup before INSERT in fixtures:
```python
# Pre-cleanup: handle stale data from failed previous teardowns
await _cleanup_e2e_meeting(db_service, "E2E-TEST-001")
# Then insert fresh data
await db_service.execute_transaction(insert_ops)
```

## Example

File: `tests/e2e/conftest.py` — `seed_meeting_data` fixture

Before (broken):
```python
# Teardown — silently fails due to PL/SQL + error detection conflict
try:
    await db_service.execute_transaction([
        (TEST_CLEANUP_EMAIL_LOGS, {"pattern": "E2E-TEST-001"}),
        (TEST_CLEANUP_MEETINGS, {"pattern": "E2E-TEST-001"}),
    ])
except Exception:
    pass  # Data persists!
```

After (working):
```python
# Teardown — individual statements, each independently succeeds/fails
await _cleanup_e2e_meeting(db_service, "E2E-TEST-001")
```
