import sqlite3
import json
import os
import threading
from datetime import datetime, timedelta
from typing import Optional


class CheckpointManager:
    def __init__(self, db_path: str = "scraper/data/checkpoints.db"):
        os.makedirs(os.path.dirname(db_path), exist_ok=True)
        self.db_path = db_path
        self._conn = sqlite3.connect(db_path, check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        self._lock = threading.Lock()
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

    def mark_completed(self, batch_id: int, asin: str, result: dict):
        now = datetime.utcnow().isoformat()
        with self._lock, self._conn:
            self._conn.execute(
                "UPDATE asin_progress SET status='completed', result_json=?, updated_at=? "
                "WHERE batch_id=? AND asin=?",
                (json.dumps(result), now, batch_id, asin),
            )
            self._conn.execute(
                "UPDATE batches SET completed = completed + 1 WHERE batch_id=?",
                (batch_id,),
            )

    def mark_failed(self, batch_id: int, asin: str, error: str):
        now = datetime.utcnow().isoformat()
        with self._lock, self._conn:
            self._conn.execute(
                "UPDATE asin_progress SET attempts = attempts + 1, last_error=?, updated_at=? "
                "WHERE batch_id=? AND asin=?",
                (error, now, batch_id, asin),
            )
            self._conn.execute(
                "UPDATE batches SET failed = failed + 1 WHERE batch_id=?",
                (batch_id,),
            )

    def get_remaining(self, batch_id: int) -> list:
        with self._lock:
            cur = self._conn.execute(
            "SELECT asin FROM asin_progress "
            "WHERE batch_id=? AND (status='pending' OR (status='failed' AND attempts < 3))",
                (batch_id,),
            )
            return [row["asin"] for row in cur.fetchall()]

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
