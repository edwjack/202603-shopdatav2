---
id: oracle-plsql-block-parallel-dml-deadlock
name: oracle-plsql-block-parallel-dml-deadlock
description: |
  Multiple DML statements inside a single PL/SQL BEGIN/END block executed via SQLcl subprocess
  can trigger ORA-12860 (deadlock detected while waiting for a sibling row lock) when Oracle
  parallelizes the statements and worker processes conflict on the same rows.
source: teamvibe session 2026-02-26 — resetSession handler deadlock
triggers:
  - ORA-12860
  - deadlock sibling row lock
  - PL/SQL block DELETE multiple tables
  - sqlcl parallel DML deadlock
  - BEGIN DELETE FROM multiple tables END
quality: 0.85
---

# Oracle PL/SQL Block Parallel DML Deadlock (ORA-12860)

## The Insight

When you execute multiple DML statements (DELETE, UPDATE) in a single PL/SQL `BEGIN...END` block via SQLcl subprocess, Oracle may parallelize the operations. If two statements touch the same table (e.g., a DELETE with a subquery referencing the same table another DELETE targets), Oracle's parallel workers can deadlock on sibling row locks — ORA-12860.

**The principle:** In SQLcl subprocess adapters, split multi-table DML into separate sequential `db.execute()` calls instead of combining them in one PL/SQL block. The ~1-3s per-call overhead is acceptable; the deadlock is not.

## Why This Matters

```
ORA-12860: deadlock detected while waiting for a sibling row lock
ORA-06512: at line 3
```

This error is non-deterministic — it depends on Oracle's query optimizer choosing parallel execution, which varies by table statistics, data volume, and system load. A PL/SQL block that works in dev with 5 rows may deadlock in production with 30+ rows.

## Recognition Pattern

You're likely hitting this when:
- Using SQLcl subprocess (not native OCI driver) as the DB adapter
- A PL/SQL `BEGIN...END` block contains multiple DELETE/UPDATE statements
- The statements have FK relationships or subqueries referencing the same tables
- Error: `ORA-12860: deadlock detected while waiting for a sibling row lock`

Common trigger pattern:
```sql
-- This can deadlock:
BEGIN
  DELETE FROM child_table WHERE parent_id IN (SELECT id FROM parent_table WHERE ...);
  DELETE FROM parent_table WHERE ...;  -- parallel workers conflict
  UPDATE other_table SET ... WHERE ...;
END;
```

## The Approach

**Split into sequential calls.** Each `db.execute()` runs independently, eliminating intra-block parallelism conflicts:

```typescript
// BAD — single PL/SQL block, parallel DML can deadlock
await db.execute(`
BEGIN
  DELETE FROM round2_team_parents WHERE round2_team_id IN (SELECT id FROM teams WHERE session_id = ...);
  DELETE FROM team_members WHERE team_id IN (SELECT id FROM teams WHERE session_id = ...);
  DELETE FROM teams WHERE session_id = ...;
  UPDATE participants SET ...;
  UPDATE hackathon_sessions SET ...;
END;
`);

// GOOD — sequential calls, no parallel DML conflict
await db.execute(`DELETE FROM round2_team_parents WHERE round2_team_id IN (SELECT id FROM teams WHERE session_id = ... AND round_number = 2)`);
await db.execute(`DELETE FROM team_members WHERE team_id IN (SELECT id FROM teams WHERE session_id = ...)`);
await db.execute(`DELETE FROM teams WHERE session_id = ...`);
await db.execute(`UPDATE participants SET ... WHERE session_id = ...`);
await db.execute(`UPDATE hackathon_sessions SET ... WHERE id = ...`);
```

**Alternative** (if you need atomicity): Disable parallel DML within the block:
```sql
BEGIN
  EXECUTE IMMEDIATE 'ALTER SESSION DISABLE PARALLEL DML';
  DELETE FROM ...;
  DELETE FROM ...;
END;
```

**Also remember FK ordering:** Delete child tables before parent tables:
`round2_team_parents` → `team_members` → `teams` (not the reverse).

## Example

In teamvibe, the `handleResetSession` handler combined 5 DML statements in one `BEGIN...END` block. With 30 participants and 15 teams, Oracle parallelized the DELETEs and two workers deadlocked on `teams` rows (one from the `team_members` subquery, one from the direct DELETE). Splitting into 5 sequential `db.execute()` calls fixed the deadlock with no noticeable latency increase (~5s total vs ~3s for the block that deadlocked 50% of the time).
