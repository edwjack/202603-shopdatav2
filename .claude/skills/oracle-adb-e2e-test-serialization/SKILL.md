---
id: oracle-adb-e2e-test-serialization
name: oracle-adb-e2e-test-serialization
description: Oracle ADB latency (~7s/query) cascades catastrophically in parallel test execution. Tests must run sequentially and account for multi-query handler completion.
source: conversation
triggers:
  - "Timeout waiting for room_state"
  - "Request context disposed"
  - "Playwright timeout Oracle"
  - "vitest hookTimeout"
  - "joinRoom timeout"
  - "messages not appearing after send"
  - "workers Oracle contention"
quality: high
---

# Oracle ADB E2E Test Serialization

## The Insight

Oracle ADB queries take ~7s each. When a WebSocket handler does N sequential DB calls, the total latency is N*7s. Running M parallel test workers means M*N concurrent DB calls, which causes connection pool exhaustion and cascading timeouts across ALL tests — not just the slow ones.

The fix is NOT "increase all timeouts". The fix is **eliminate parallelism** at every layer (Playwright workers, Vitest file parallelism) and **explicitly wait for multi-query handlers to complete** before asserting.

## Why This Matters

Without this knowledge:
- Tests pass individually (`npx playwright test -g "MS-002"`) but fail in suite runs
- Flaky failures appear random — different tests fail each run
- Increasing timeouts helps some tests but breaks others (longer tests block the queue)
- Messages sent immediately after navigating to a chat room are silently dropped

## Recognition Pattern

You're hitting this when:
- Building E2E tests for an app backed by Oracle ADB (not Postgres/MySQL)
- Tests pass in isolation but fail when run as a suite
- Error messages include "Timeout waiting for..." or "Request context disposed"
- `join_room` WebSocket handler does 3+ sequential DB queries before emitting `room_state`
- Messages sent right after joining a room never appear in the chat

## The Approach

### 1. Serialize ALL test execution

```typescript
// playwright.config.ts
workers: 1,  // NEVER use parallel workers with Oracle ADB

// vitest.config.ts
fileParallelism: false,  // Run test files sequentially
```

### 2. Account for multi-query handler completion

The `join_room` WS handler does 3 Oracle calls (~21s). Messages sent before it completes are silently dropped. Add explicit waits in test fixtures:

```typescript
// auth.fixture.ts - createRoomAndJoin
await page.goto(`/chat/${room.roomId}`);
// Wait for WebSocket join_room to complete (3 Oracle DB calls ~7s each = ~21s)
await page.waitForTimeout(25000);
```

### 3. Set timeouts at 2-3x the Oracle call chain length

| Operation | DB calls | Base time | Safe timeout |
|-----------|----------|-----------|-------------|
| Create user | 1 | 7s | 20s |
| Create room | 2 | 14s | 30s |
| Join room (WS) | 3 | 21s | 60s |
| Send message | 2 | 14s | 30s |
| Full user journey | 8+ | 56s+ | 120s |

### 4. Set global test timeout to accommodate fixtures

```typescript
// playwright.config.ts
timeout: 120000,  // 2 min (fixture setup alone can take 30s+)

// vitest.config.ts
testTimeout: 120000,
hookTimeout: 120000,  // beforeAll creates users/rooms via Oracle
```

## Example

```typescript
// BAD: Works in isolation, fails in suite (4 workers hit Oracle simultaneously)
test('send message', async ({ page }) => {
  await page.goto(`/chat/${roomId}`);
  await page.fill('[data-testid="message-input"]', 'hello');
  await page.press('[data-testid="message-input"]', 'Enter');
  await expect(page.locator('text=hello')).toBeVisible({ timeout: 5000 }); // FAILS
});

// GOOD: Waits for join_room completion, generous timeouts
test('send message', async ({ page }) => {
  await page.goto(`/chat/${roomId}`);
  await page.waitForTimeout(25000); // Wait for 3 Oracle DB calls in join_room
  await page.fill('[data-testid="message-input"]', 'hello');
  await page.press('[data-testid="message-input"]', 'Enter');
  await expect(page.locator('text=hello')).toBeVisible({ timeout: 30000 });
});
```
