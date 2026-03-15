# Skill Output Patterns

Patterns for how skills produce and format their output.

## Template Pattern

Use `assets/` directory for output templates that get populated with data.

```
skill-name/
├── SKILL.md
└── assets/
    └── report-template.md
```

SKILL.md references:
```markdown
Read [assets/report-template.md](assets/report-template.md) and populate placeholders:
- `{{PROJECT_NAME}}` → detected project name
- `{{DATE}}` → current date
- `{{RESULTS}}` → generated results
```

**When to use:** Consistent output format across invocations. Reports, changelogs, READMEs.

## Example-Driven Pattern

Show before/after examples to guide Claude's output.

```markdown
## Output Format

**Input:**
```js
const x = require('lodash')
```

**Expected output:**
```js
import x from 'lodash'
```
```

**When to use:** Code transformations, formatting rules, migration patterns.

## Table Output Pattern

Structure results as markdown tables for scannable output.

```markdown
## Output

Report results as a table:

| File | Status | Issues |
|------|--------|--------|
| src/app.ts | Pass | 0 |
| src/db.ts | Fail | 2 |
```

**When to use:** Status reports, audit results, multi-item summaries.

## Code Generation Pattern

Generate code files from specifications.

```markdown
## Output

Create the following file:

**Path:** `src/models/<name>.ts`

**Structure:**
- Export interface with fields from spec
- Export validation function
- Export factory function with defaults

Follow existing patterns in `src/models/` for naming and style.
```

**When to use:** Scaffolding, boilerplate generation, schema-to-code workflows.

## File Creation Pattern

Create multiple files as part of skill output.

```markdown
## Output Files

Create these files:

1. `<name>/index.ts` — main entry point
2. `<name>/types.ts` — TypeScript interfaces
3. `<name>/test.ts` — unit tests

Use [assets/component-template.ts](assets/component-template.ts) as starting point.
```

**When to use:** Project scaffolding, component creation, multi-file output.

## Summary + Detail Pattern

Provide a brief summary followed by expandable details.

```markdown
## Output

First, print a one-line summary:
> Processed 5 files: 3 passed, 2 failed.

Then print detailed results for failures only, with file path, line number, and error message.
```

**When to use:** When output can be large but user usually only needs the summary.
