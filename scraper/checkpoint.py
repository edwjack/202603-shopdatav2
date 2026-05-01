import sqlite3
import json
import os
import threading
from datetime import datetime, timedelta
from typing import Optional


class CheckpointManager:
    # Status transitions:
    #   pending → scraped (worker got data)
    #   scraped → persisted (Rails accepted the batch — durable)
    #   pending → pending [attempts++] (retryable failure, attempts < MAX_ATTEMPTS)
    #   pending → failed (attempts >= MAX_ATTEMPTS, terminal)
    #
    # get_remaining returns rows that are pending OR scraped-but-not-persisted
    # so a Rails outage doesn't cause silent data loss on resume (F5 fix).

    MAX_ATTEMPTS = 3

    def __init__(self, db_path: str = "scraper/data/checkpoints.db"):
        os.makedirs(os.path.dirname(db_path), exist_ok=True)
        self.db_path = db_path
        self._conn = sqlite3.connect(db_path, check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        self._lock = threading.Lock()
        # WAL improves concurrent read/write throughput on the per-ASIN
        # progress table — critical at 50K scale where every worker writes
        # for every fetch (H4 fix).
        self._conn.execute("PRAGMA journal_mode=WAL")
        self._conn.execute("PRAGMA synchronous=NORMAL")
        self._init_schema()

    def close(self):
        """Close the SQLite connection."""
        with self._lock:
            if self._conn:
                self._conn.close()
                self._conn = None

    def _init_schema(self):
        with self._conn:
            self._conn.executescript("""
                CREATE TABLE IF NOT EXISTS batches (
                    batch_id  INTEGER PRIMARY KEY,
                    total     INTEGER,
                    completed INTEGER DEFAULT 0,
                    failed    INTEGER DEFAULT 0,
                    created_at TEXT,
                    status    TEXT DEFAULT 'in_progress'
                );

                CREATE TABLE IF NOT EXISTS asin_progress (
                    batch_id    INTEGER,
                    asin        TEXT,
                    channel     TEXT,
                    status      TEXT DEFAULT 'pending',
                    attempts    INTEGER DEFAULT 0,
                    last_error  TEXT,
                    result_json TEXT,
                    updated_at  TEXT,
                    PRIMARY KEY (batch_id, asin)
                );

                CREATE INDEX IF NOT EXISTS idx_asin_progress_status
                    ON asin_progress (batch_id, status);
            """)

    # ------------------------------------------------------------------
    def init_batch(self, batch_id: int, asins: list, channel_map: dict = None):
        now = datetime.utcnow().isoformat()
        channel_map = channel_map or {}
        with self._lock, self._conn:
            self._conn.execute(
                "INSERT OR REPLACE INTO batches (batch_id, total, completed, failed, created_at, status) "
                "VALUES (?, ?, 0, 0, ?, 'in_progress')",
                (batch_id, len(asins), now),
            )
            self._conn.executemany(
                "INSERT OR IGNORE INTO asin_progress (batch_id, asin, channel, status, attempts, updated_at) "
                "VALUES (?, ?, ?, 'pending', 0, ?)",
                [
                    (batch_id, asin, channel_map.get(asin, ""), now)
                    for asin in asins
                ],
            )

    def mark_scraped(self, batch_id: int, asin: str, result: dict):
        """Worker successfully fetched the page — but not yet durably persisted
        in Rails. Status='scraped' makes this row eligible for resume so a
        Rails outage doesn't silently drop the result."""
        now = datetime.utcnow().isoformat()
        with self._lock, self._conn:
            self._conn.execute(
                "UPDATE asin_progress SET status='scraped', result_json=?, updated_at=? "
                "WHERE batch_id=? AND asin=?",
                (json.dumps(result), now, batch_id, asin),
            )

    def mark_persisted(self, batch_id: int, asin: str):
        """Rails confirmed the batch — terminal success state."""
        now = datetime.utcnow().isoformat()
        with self._lock, self._conn:
            self._conn.execute(
                "UPDATE asin_progress SET status='persisted', updated_at=? "
                "WHERE batch_id=? AND asin=?",
                (now, batch_id, asin),
            )
            self._conn.execute(
                "UPDATE batches SET completed = completed + 1 WHERE batch_id=?",
                (batch_id,),
            )

    # Backwards-compat shim for callers that still use the old single-step
    # mark_completed. New code should call mark_scraped + mark_persisted.
    def mark_completed(self, batch_id: int, asin: str, result: dict):
        self.mark_scraped(batch_id, asin, result)
        self.mark_persisted(batch_id, asin)

    def mark_failed(self, batch_id: int, asin: str, error: str):
        """Increment attempts. Once attempts >= MAX_ATTEMPTS, transition to
        terminal status='failed' so retry queries stop pulling this row.
        Without the transition, get_remaining returned the row forever
        (C3/F6 bug)."""
        now = datetime.utcnow().isoformat()
        with self._lock, self._conn:
            cur = self._conn.execute(
                "SELECT attempts, status FROM asin_progress WHERE batch_id=? AND asin=?",
                (batch_id, asin),
            )
            row = cur.fetchone()
            if row is None:
                return
            new_attempts = (row["attempts"] or 0) + 1
            new_status = "failed" if new_attempts >= self.MAX_ATTEMPTS else "pending"
            self._conn.execute(
                "UPDATE asin_progress SET attempts=?, last_error=?, status=?, updated_at=? "
                "WHERE batch_id=? AND asin=?",
                (new_attempts, error, new_status, now, batch_id, asin),
            )
            # batches.failed only counts terminal failures, not every attempt.
            if new_status == "failed":
                self._conn.execute(
                    "UPDATE batches SET failed = failed + 1 WHERE batch_id=?",
                    (batch_id,),
                )

    def get_remaining(self, batch_id: int) -> list:
        """Pending OR scraped-but-not-persisted (Rails outage replay).
        Excludes terminal 'failed' (attempts maxed) and 'persisted'."""
        with self._lock:
            cur = self._conn.execute(
                "SELECT asin FROM asin_progress "
                "WHERE batch_id=? AND status IN ('pending','scraped')",
                (batch_id,),
            )
            return [row["asin"] for row in cur.fetchall()]

    def get_unpersisted_results(self, batch_id: int = None) -> list:
        """Return rows in status='scraped' (data fetched but not in Rails).
        Used by replay tool to resend after a Rails outage."""
        with self._lock:
            if batch_id is None:
                cur = self._conn.execute(
                    "SELECT batch_id, asin, result_json FROM asin_progress "
                    "WHERE status='scraped' AND result_json IS NOT NULL"
                )
            else:
                cur = self._conn.execute(
                    "SELECT batch_id, asin, result_json FROM asin_progress "
                    "WHERE batch_id=? AND status='scraped' AND result_json IS NOT NULL",
                    (batch_id,),
                )
            out = []
            for row in cur.fetchall():
                try:
                    out.append({
                        "batch_id": row["batch_id"],
                        "asin": row["asin"],
                        "result": json.loads(row["result_json"]),
                    })
                except json.JSONDecodeError:
                    continue
            return out

    def get_progress(self, batch_id: int) -> dict:
        with self._lock:
            row = self._conn.execute(
            "SELECT total, completed, failed FROM batches WHERE batch_id=?",
                (batch_id,),
            ).fetchone()
        if row is None:
            return {"total": 0, "completed": 0, "failed": 0, "remaining": 0, "progress_pct": 0.0}
        total = row["total"]
        completed = row["completed"]
        failed = row["failed"]
        remaining = len(self.get_remaining(batch_id))
        pct = (completed / total * 100.0) if total > 0 else 0.0
        return {
            "total": total,
            "completed": completed,
            "failed": failed,
            "remaining": remaining,
            "progress_pct": round(pct, 2),
        }

    def get_batch_status(self, batch_id: int) -> str:
        with self._lock:
            row = self._conn.execute(
                "SELECT status FROM batches WHERE batch_id=?", (batch_id,)
            ).fetchone()
        if row is None:
            return "not_found"
        return row["status"]

    def set_batch_status(self, batch_id: int, status: str):
        """Persist batch lifecycle state (in_progress / completed / failed).
        Without this, batches.status was forever 'in_progress' (F7 bug)."""
        if status not in ("in_progress", "completed", "failed"):
            raise ValueError(f"invalid batch status: {status}")
        with self._lock, self._conn:
            self._conn.execute(
                "UPDATE batches SET status=? WHERE batch_id=?",
                (status, batch_id),
            )

    def cleanup_old(self, days: int = 30):
        cutoff = (datetime.utcnow() - timedelta(days=days)).isoformat()
        with self._lock, self._conn:
            self._conn.execute(
                "DELETE FROM asin_progress WHERE batch_id IN "
                "(SELECT batch_id FROM batches WHERE created_at < ?)",
                (cutoff,),
            )
            self._conn.execute(
                "DELETE FROM batches WHERE created_at < ?", (cutoff,)
            )
