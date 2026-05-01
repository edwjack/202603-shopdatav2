"""Replay fallback batches to Rails after a Rails outage.

The scraper's BatchResultBuffer writes scraper/data/fallback_*.json whenever
all 3 retries to /api/products/batch_upsert fail. This tool re-sends them
and, on Rails 200, transitions the corresponding checkpoint rows from
'scraped' to 'persisted' so resume semantics are correct (F5 durability tail).

Usage:
    python scripts/replay_fallback.py [--checkpoint scraper/data/checkpoints.db]
                                      [--endpoint http://localhost:3210/api/products/batch_upsert]
                                      [--token "$SCRAPER_API_TOKEN"]
                                      [--keep-on-success]   # don't delete fallback files
                                      [--dry-run]

Behavior:
    - Iterates scraper/data/fallback_*.json (sorted by timestamp).
    - For each file, POSTs payload to Rails (Bearer token).
    - On 2xx: calls checkpoint.mark_persisted for each (batch_id, asin)
      pair captured when the fallback was written, then deletes the file
      unless --keep-on-success.
    - On non-2xx or network error: leaves file in place, exits non-zero.
    - Walks the unpersisted-in-DB list for batches that have 'scraped' rows
      but no fallback file (e.g., scraper crashed mid-flush before writing
      fallback) and re-sends those too.

Exit codes:
    0 = all fallbacks replayed successfully
    1 = at least one batch failed; safe to re-run
    2 = configuration error
"""
import argparse
import glob
import json
import os
import sys

import httpx


DEFAULT_CHECKPOINT_DB = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "scraper",
    "data",
    "checkpoints.db",
)
DEFAULT_FALLBACK_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "scraper",
    "data",
)


def _post(endpoint: str, token: str, products: list, batch_id: int) -> tuple[bool, str]:
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }
    payload = {"products": products, "batch_id": batch_id}
    try:
        with httpx.Client(http2=True, timeout=60.0) as client:
            r = client.post(endpoint, json=payload, headers=headers)
            if r.is_success:
                return True, f"HTTP {r.status_code}"
            return False, f"HTTP {r.status_code}: {r.text[:200]}"
    except Exception as exc:  # noqa: BLE001
        return False, f"exception: {exc}"


def _is_already_persisted(checkpoint, batch_id, asin) -> bool:
    """Idempotency filter: skip rows that checkpoint already says are
    persisted (a previous replay or a late on_persisted callback may have
    transitioned them)."""
    if checkpoint is None or batch_id is None or not asin:
        return False
    try:
        with checkpoint._lock:
            row = checkpoint._conn.execute(
                "SELECT status FROM asin_progress WHERE batch_id=? AND asin=?",
                (batch_id, asin),
            ).fetchone()
        return row is not None and row["status"] == "persisted"
    except Exception:
        return False


def replay_file(path: str, endpoint: str, token: str, checkpoint, dry_run: bool) -> bool:
    with open(path, "r", encoding="utf-8") as fh:
        payload = json.load(fh)
    items = payload.get("items")
    if not items:
        # Old fallback format (pre-PR3) — has 'products' but no batch_id/asin.
        # Best-effort: send to Rails but skip checkpoint transition.
        # Rails ProductsController#batch_upsert uses find_or_initialize_by(asin),
        # so duplicate sends are idempotent at the DB layer.
        products = payload.get("products", [])
        if not products:
            return True  # empty file
        if dry_run:
            print(f"[dry-run] would POST {len(products)} legacy items from {path}")
            return True
        ok, info = _post(endpoint, token, products, batch_id=0)
        print(f"{'OK' if ok else 'FAIL'} {path} (legacy, {len(products)} items): {info}")
        return ok

    # Idempotency filter — drop items that the checkpoint already marks
    # persisted. Without this, a re-run after partial success would resend
    # everything (Rails dedupes via find_or_initialize_by but we still pay
    # the network and Rails-side write cost).
    fresh_items = [
        it for it in items
        if not _is_already_persisted(checkpoint, it.get("batch_id"), it.get("asin"))
    ]
    skipped = len(items) - len(fresh_items)
    if not fresh_items:
        print(f"OK {path} ({len(items)} items, all already persisted; skipping)")
        return True

    products = [it["product"] for it in fresh_items]
    pair_keys = [(it.get("batch_id"), it.get("asin")) for it in fresh_items]
    if dry_run:
        print(f"[dry-run] would POST {len(products)} items from {path} "
              f"(skipped {skipped} already-persisted)")
        return True

    batch_id_outer = max((b for b, _ in pair_keys if b), default=0)
    ok, info = _post(endpoint, token, products, batch_id=batch_id_outer)
    print(f"{'OK' if ok else 'FAIL'} {path} "
          f"({len(products)} items, skipped {skipped} already-persisted): {info}")
    if not ok:
        return False

    if checkpoint is not None:
        for b_id, asin in pair_keys:
            if b_id is None or not asin:
                continue
            try:
                checkpoint.mark_persisted(b_id, asin)
            except Exception as exc:  # noqa: BLE001
                print(f"  WARN: mark_persisted({b_id}, {asin}) → {exc}", file=sys.stderr)
    return True


def replay_unpersisted_in_db(checkpoint, endpoint: str, token: str, dry_run: bool) -> bool:
    """Find rows in checkpoint with status='scraped' but no fallback file
    (e.g., scraper crashed before writing fallback) and resend them."""
    rows = checkpoint.get_unpersisted_results()
    if not rows:
        return True
    print(f"[db-replay] {len(rows)} rows in 'scraped' state — resending")
    if dry_run:
        return True
    products = [r["result"] for r in rows]
    pair_keys = [(r["batch_id"], r["asin"]) for r in rows]
    batch_id_outer = max((b for b, _ in pair_keys if b), default=0)
    ok, info = _post(endpoint, token, products, batch_id=batch_id_outer)
    print(f"{'OK' if ok else 'FAIL'} db-replay ({len(products)} items): {info}")
    if not ok:
        return False
    for b_id, asin in pair_keys:
        try:
            checkpoint.mark_persisted(b_id, asin)
        except Exception as exc:  # noqa: BLE001
            print(f"  WARN: mark_persisted({b_id}, {asin}) → {exc}", file=sys.stderr)
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--checkpoint", default=DEFAULT_CHECKPOINT_DB)
    ap.add_argument("--fallback-dir", default=DEFAULT_FALLBACK_DIR)
    ap.add_argument("--endpoint", default=os.environ.get(
        "RAILS_BATCH_ENDPOINT",
        "http://localhost:3210/api/products/batch_upsert",
    ))
    ap.add_argument("--token", default=os.environ.get("SCRAPER_API_TOKEN", ""))
    ap.add_argument("--keep-on-success", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    if not args.token:
        print("ERROR: SCRAPER_API_TOKEN not set", file=sys.stderr)
        return 2

    # Lazy import — checkpoint module lives under scraper/, add to path.
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "scraper"))
    try:
        from checkpoint import CheckpointManager
        checkpoint = CheckpointManager(db_path=args.checkpoint) if os.path.exists(args.checkpoint) else None
    except Exception as exc:  # noqa: BLE001
        print(f"WARN: could not open checkpoint DB at {args.checkpoint}: {exc}", file=sys.stderr)
        checkpoint = None

    files = sorted(glob.glob(os.path.join(args.fallback_dir, "fallback_*.json")))
    print(f"replay: {len(files)} fallback file(s) found")

    overall_ok = True
    for path in files:
        ok = replay_file(path, args.endpoint, args.token, checkpoint, args.dry_run)
        if ok and not args.keep_on_success and not args.dry_run:
            try:
                os.remove(path)
            except OSError as exc:
                print(f"  WARN: could not remove {path}: {exc}", file=sys.stderr)
        if not ok:
            overall_ok = False

    if checkpoint is not None:
        if not replay_unpersisted_in_db(checkpoint, args.endpoint, args.token, args.dry_run):
            overall_ok = False
        checkpoint.close()

    return 0 if overall_ok else 1


if __name__ == "__main__":
    sys.exit(main())
