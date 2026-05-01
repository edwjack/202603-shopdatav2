---
id: esm-dotenv-hoisting-trap
name: esm-dotenv-hoisting-trap
description: >
  When using TypeScript/ESM with dotenv, import hoisting causes module-level
  process.env checks to run BEFORE dotenv.config() executes, even if dotenv.config()
  appears first in source code. Use node --env-file=.env instead.
source: conversation
triggers:
  - "JWT_SECRET environment variable must be set"
  - "process.env undefined at module level"
  - "dotenv.config not working"
  - "env var undefined despite .env file"
  - "ESM import hoisting env"
  - "auth.ts throw Error environment variable"
quality: validated
---

# ESM Import Hoisting Breaks dotenv Module-Level Checks

## The Insight

In ESM/TypeScript, **all `import` statements are hoisted and resolved before any executable code runs**, regardless of their position in source. This means `dotenv.config()` on line 2 runs AFTER all imported modules have been fully loaded and their module-level code executed.

The mental model: **imports are not sequential statements — they are declarations resolved at parse time.**

## Why This Matters

This pattern silently breaks any module that checks `process.env.*` at the top level:

```typescript
// index.ts
import dotenv from 'dotenv';    // line 1
dotenv.config();                 // line 2 — LOOKS like it runs first
import { verifyToken } from './middleware/auth';  // line 11 — actually loads FIRST
```

```typescript
// auth.ts — this runs BEFORE dotenv.config()
const JWT_SECRET = process.env.JWT_SECRET;  // undefined!
if (!JWT_SECRET) {
  throw new Error('JWT_SECRET environment variable must be set');  // BOOM
}
```

Symptom: `Error: JWT_SECRET environment variable must be set` even though `.env` file exists and contains the value.

## Recognition Pattern

- Backend crashes on startup with "environment variable must be set" errors
- `.env` file exists and contains the correct values
- `dotenv` is installed and `dotenv.config()` is called in the entry file
- The failing check is in an **imported module**, not the entry file itself
- Using `tsx`, `ts-node`, or native ESM (`"type": "module"`)

## The Approach

**Don't use `dotenv.config()` in ESM entry files when imported modules check env vars at module level.**

Instead, load env vars at the Node.js runtime level, before ANY JavaScript executes:

```bash
# CORRECT: env vars loaded before any module code
node --env-file=.env node_modules/.bin/tsx watch src/index.ts

# WRONG: dotenv.config() runs after imports are resolved
npx tsx watch src/index.ts
```

Decision heuristic:
1. Does any imported module read `process.env` at the top level (not inside a function)?
2. If YES → env vars must be loaded BEFORE Node.js starts resolving modules
3. Use `node --env-file=.env` (Node 20.6+) or `-r dotenv/config` preload

## Example

TeamVibe backend startup command:
```bash
# backend/
nohup node --env-file=.env node_modules/.bin/tsx watch src/index.ts > /tmp/teamvibe-backend.log 2>&1 &
```

Files involved:
- `backend/src/index.ts:1-2` — dotenv.config() (too late)
- `backend/src/middleware/auth.ts:5-8` — module-level JWT_SECRET check (runs first)
