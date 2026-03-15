# Skill Workflow Patterns

Design patterns for structuring skill execution flows.

## Sequential Workflow

Step-by-step execution where each step depends on the previous.

```markdown
### Step 1: Gather Input
Read config file or ask user for parameters.

### Step 2: Process
Transform input using scripts or tool calls.

### Step 3: Output
Write results to files or display to user.
```

**When to use:** Most skills. Default pattern when steps have dependencies.

## Conditional Logic

Branch execution based on detected state.

```markdown
## Execution

Detect project type first:
- If `package.json` exists → Node.js workflow
- If `requirements.txt` exists → Python workflow
- Otherwise → ask user

### Node.js Workflow
...

### Python Workflow
...
```

**When to use:** Skills that support multiple environments, languages, or configurations.

## Loop / Iteration

Repeat an action across a collection.

```markdown
## Execution

For each file matching `src/**/*.ts`:
1. Read the file
2. Check for pattern X
3. If found, apply transformation Y
4. Report result
```

**When to use:** Batch operations, multi-project tasks, bulk transformations.

## Error Handling

Define fallback behavior when steps fail.

```markdown
## Error Handling

| Error | Recovery |
|-------|----------|
| File not found | Skip and warn user |
| API timeout | Retry once, then abort with message |
| Invalid input | Ask user to correct |

Never silently swallow errors. Always report what failed and why.
```

**When to use:** Every skill should define error handling for likely failure modes.

## Gated Execution

Require explicit user confirmation before destructive or irreversible steps.

```markdown
### Step 3: Apply Changes

**Confirm with user before proceeding:**
- Show list of files to be modified
- Show summary of changes
- Wait for explicit approval

Then execute changes.
```

**When to use:** Skills that delete, overwrite, or deploy. Any destructive operation.

## Parallel Fan-Out

Execute independent sub-tasks concurrently, then merge results.

```markdown
## Execution

Run these checks in parallel:
1. Lint check → pass/fail
2. Type check → pass/fail
3. Test suite → pass/fail

Then combine results into summary table.
```

**When to use:** Independent validations, multi-repo operations, parallel data fetching.
