# SQLcl Subprocess Query Queue Pattern

## The Insight

SQLcl spawns a new Java process for EVERY query. Unlike connection pooling in traditional DB drivers, each `spawn('sql', ...)` creates a heavyweight process (~50MB). When WebSocket events trigger multiple concurrent queries (e.g., 10 users joining simultaneously), you can easily spawn 30-50 processes, blocking the entire system.

**The principle**: SQLcl subprocess adapter needs an explicit concurrency limiter because there's no built-in connection pooling.

## Why This Matters

Symptoms when you don't know this:
- Backend becomes unresponsive under load
- `ps aux | grep sqlcl` shows 40+ processes
- WebSocket callbacks timeout waiting for DB responses
- Server appears "hung" but no error messages

In this project, 10 simulated users joining triggered 48 concurrent sqlcl processes, completely blocking the backend.

## Recognition Pattern

- Using SQLcl via subprocess (`spawn('sql', ...)`) for Oracle DB
- WebSocket handlers making DB queries
- Multiple concurrent users/connections
- Symptoms: timeout errors, unresponsive server, many Java processes

## The Approach

1. **Never call sqlcl directly** - Always route through a queue
2. **Limit concurrent processes** - 3-5 max for SQLcl (heavy)
3. **Queue pending requests** - FIFO with promise resolution
4. **Background processing** - For slow multi-query operations, return callback immediately

Decision heuristic: "Before any DB query, ask: what if 50 users hit this endpoint simultaneously?"

## Example

```typescript
// backend/src/config/database.ts
class QueryQueue {
  private queue: Array<() => Promise<void>> = [];
  private running = 0;
  private maxConcurrent = 3; // SQLcl processes are heavy (~50MB each)

  async add<T>(fn: () => Promise<T>): Promise<T> {
    return new Promise((resolve, reject) => {
      const task = async () => {
        try {
          resolve(await fn());
        } catch (err) {
          reject(err);
        } finally {
          this.running--;
          this.processNext();
        }
      };
      this.queue.push(task);
      this.processNext();
    });
  }

  private processNext() {
    if (this.running >= this.maxConcurrent || this.queue.length === 0) return;
    this.running++;
    const task = this.queue.shift();
    if (task) task();
  }
}

const queryQueue = new QueryQueue();

// All DB methods route through queue
async query(sql: string): Promise<QueryResult> {
  return queryQueue.add(() => this._queryInternal(sql));
}
```

## Related Files

- `backend/src/config/database.ts` - QueryQueue implementation
- `backend/src/websocket/handlers.ts` - Background processing pattern for slow operations

## Triggers

- sqlcl subprocess
- too many processes
- websocket timeout
- database blocking
- concurrent sqlcl
- spawn sql process limit
