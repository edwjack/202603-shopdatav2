---
id: sqlcl-plsql-json-consolidation
name: sqlcl-plsql-json-consolidation
description: When using SQLcl subprocess as DB adapter, consolidate N sequential DB calls into a single PL/SQL function returning JSON to eliminate per-call overhead
source: conversation
triggers:
  - "slow db"
  - "too many db calls"
  - "sqlcl performance"
  - "sequential db.query"
  - "sequential db.execute"
  - "QueryQueue bottleneck"
  - "teams creation slow"
  - "matching slow"
quality: high
scope: project
---

# SQLcl Subprocess → PL/SQL Function Consolidation

## The Insight

Each `db.query()` or `db.execute()` call through the SQLcl subprocess adapter has a fixed overhead of ~1-3 seconds (process communication, SQL parsing, result serialization). The overhead is **per-call, not per-row**. A simple INSERT takes as long to dispatch as a complex JOIN. Therefore, the optimization lever is **reducing call count**, not query complexity.

The principle: **Move loops from Node.js into PL/SQL. Return structured JSON from a single function call.**

## Why This Matters

A typical CRUD operation that seems simple — "create a team with members" — can expand to 5-9 sequential DB calls:
1. SELECT next number
2. INSERT team
3. SELECT team ID
4. INSERT member 1
5. INSERT member 2
6. UPDATE participant statuses

At ~2s per call, that's 10-18 seconds for what should be instant. Users perceive this as a hang. The `QueryQueue` (concurrency=3) compounds the problem when multiple operations queue up.

**Real example from this project**: `handleCloseSelection` with 5 teams = 36 DB calls = ~60 seconds. After consolidation = 1 DB call = ~3 seconds.

## Recognition Pattern

You should apply this when you see:
- Multiple `await db.query()` / `await db.execute()` calls in sequence within a single endpoint or handler
- A loop in Node.js where each iteration makes DB calls
- Users reporting "slow" or "hanging" on operations that should be fast
- `[QueryQueue]` log spam showing high queue depths

## The Approach

1. **Identify the boundary**: Find the Node.js function that makes N sequential DB calls
2. **Create a PL/SQL function**: `CREATE OR REPLACE FUNCTION fn_name(...) RETURN CLOB`
3. **Move ALL logic into PL/SQL**: Cursors, BULK COLLECT, loops — all inside the function
4. **Return JSON via CLOB**: Use `JSON_ARRAYAGG`/`JSON_OBJECT` for result sets, or manual string concatenation for complex structures
5. **Call once from Node.js**: `SELECT fn_name(...) as RESULT FROM DUAL`
6. **Parse JSON in Node.js**: `JSON.parse(result.rows[0].RESULT)`

### PL/SQL Pattern Template

```sql
CREATE OR REPLACE FUNCTION do_complex_operation(
  p_session_id RAW,
  p_param2 NUMBER
) RETURN CLOB AS
  v_result CLOB := '[';
  v_first BOOLEAN := TRUE;
  TYPE t_raw_tab IS TABLE OF RAW(16);
  v_ids t_raw_tab;
BEGIN
  -- BULK COLLECT for batch operations
  SELECT id BULK COLLECT INTO v_ids FROM some_table WHERE ...;

  -- Loop with DML inside PL/SQL (no Node.js round-trips)
  FOR i IN 1..v_ids.COUNT LOOP
    INSERT INTO ... VALUES (...);
    UPDATE ... SET ... WHERE id = v_ids(i);

    -- Build JSON inline
    IF NOT v_first THEN v_result := v_result || ','; END IF;
    v_result := v_result || '{"id":"' || RAWTOHEX(v_ids(i)) || '"}';
    v_first := FALSE;
  END LOOP;

  COMMIT;
  v_result := v_result || ']';
  RETURN v_result;
END;
```

### Node.js Calling Pattern

```typescript
const result = await db.query(`
  SELECT do_complex_operation(
    HEXTORAW('${sessionRaw}'),
    ${paramValue}
  ) as RESULT FROM DUAL
`);
const data = JSON.parse(result.rows[0].RESULT as string);
```

## Example

**Before** (9 DB calls, ~18s):
```
getNextTeamNumber → db.query
getTeam1Info → db.query
getTeam2Info → db.query
insertTeam → db.execute
getTeamId → db.query
insertParent1 → db.execute
insertParent2 → db.execute
copyMembers → db.execute
getMembers → db.query
```

**After** (1 DB call, ~2s):
```
SELECT create_round2_team(session_id, team1_id, team2_id) FROM DUAL
→ Returns: teamId|teamNumber|teamName|membersJSON
```

**Key gotcha**: Use `RETURNING CLOB` in `JSON_ARRAYAGG` for large result sets, and `NVL(v_result, '[]')` for empty collections to avoid NULL JSON parse errors.
