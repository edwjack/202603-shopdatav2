#!/usr/bin/env bash
# soak_100_asin_24h.sh — 100 Amazon fetches paced over 24h, real mode,
# DIRECT-only. Validates R-CARRY-13 from the 5-skill audit.
#
# Detached invocation:
#   nohup setsid bash scripts/soak_100_asin_24h.sh > /dev/null 2>&1 &
#
# Outputs:
#   data/soak/<run-id>.jsonl         — per-fetch result log
#   data/soak/<run-id>.scraper.log   — uvicorn stdout/stderr
#   data/soak/<run-id>.status        — STARTING|RUNNING|SUMMARIZING|COMPLETED|FAILED-*
#   docs/soak/100-asin-24h-2026-05-01.md — final markdown report
set -uo pipefail

PROJECT="/home/opc/202603-shopdatav2"
SOAK_DIR="$PROJECT/data/soak"
DOCS_DIR="$PROJECT/docs/soak"
RESULT_MD="$DOCS_DIR/100-asin-24h-2026-05-01.md"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
JSONL="$SOAK_DIR/$RUN_ID.jsonl"
STATUS_FILE="$SOAK_DIR/$RUN_ID.status"
SCRAPER_LOG="$SOAK_DIR/$RUN_ID.scraper.log"
SCRAPER_PID_FILE="$SOAK_DIR/$RUN_ID.scraper.pid"
TOKEN="${SCRAPER_API_TOKEN:-soak-$(openssl rand -hex 8)}"
PORT=3211
TOTAL=100
INTERVAL_SEC=$(( 86400 / TOTAL ))   # 864s = 14.4 min

# 10 well-known stable ASINs (cycled to 100 total = 10 hits each)
ASINS=(
    B0BSHF7WHW   # MacBook Pro M2 Pro
    B09B8V1LZ3   # Echo Dot 5th
    0143127748   # Body Keeps the Score (book)
    B07XJ8C8F5   # Echo Dot 4th
    B07ZPC9QD4   # AirPods Pro
    B0BDHWDR12   # Kindle Paperwhite
    B07VGRJDFY   # Nintendo Switch
    B07FZ8S74R   # Brita pitcher
    B08H93ZRK9   # known invalid baseline (404)
    B07MLCXBXZ   # known invalid baseline (404)
)

mkdir -p "$SOAK_DIR" "$DOCS_DIR"

write_status() {
    echo "$1" > "$STATUS_FILE"
}

summarize() {
    local s="$1"
    write_status "$s"
    if command -v python3 >/dev/null && [ -x "$PROJECT/scripts/soak_summarize.py" ]; then
        python3 "$PROJECT/scripts/soak_summarize.py" \
            --jsonl "$JSONL" \
            --status "$STATUS_FILE" \
            --output "$RESULT_MD" \
            --run-id "$RUN_ID" \
            --total-target "$TOTAL" 2>>"$SCRAPER_LOG" || true
    fi
}

cleanup() {
    summarize "${1:-INTERRUPTED}"
    if [ -f "$SCRAPER_PID_FILE" ]; then
        local pid
        pid="$(cat "$SCRAPER_PID_FILE" 2>/dev/null || true)"
        [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null || true
    fi
}
trap 'cleanup INTERRUPTED' INT TERM
trap 'cleanup COMPLETED' EXIT

write_status "STARTING"
echo "[$(date -u +%FT%TZ)] soak run $RUN_ID starting" >> "$SCRAPER_LOG"

# ---------------------------------------------------------------------------
# Boot scraper in real mode
# ---------------------------------------------------------------------------
cd "$PROJECT/scraper"
nohup env PYTHONDONTWRITEBYTECODE=1 \
    MOCK_EXTERNAL_APIS=false \
    SCRAPER_API_TOKEN="$TOKEN" \
    AMAZON_ZIP_CODE=90006 \
    SCRAPER_WORKERS=1 \
    .venv/bin/python -m uvicorn main:app --host 127.0.0.1 --port "$PORT" --log-level info \
    >> "$SCRAPER_LOG" 2>&1 &
SCRAPER_PID=$!
echo "$SCRAPER_PID" > "$SCRAPER_PID_FILE"
disown $SCRAPER_PID 2>/dev/null || true

# Wait up to 60s for /health
booted=0
for _ in $(seq 1 30); do
    if curl -fsS -m 2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
        booted=1
        break
    fi
    sleep 2
done
if [ "$booted" -ne 1 ]; then
    write_status "FAILED-BOOT"
    summarize "FAILED-BOOT"
    exit 1
fi

write_status "RUNNING"

# ---------------------------------------------------------------------------
# Soak loop — 100 fetches paced over 24h
# ---------------------------------------------------------------------------
START_TS=$(date -u +%s)
n_asins=${#ASINS[@]}

for i in $(seq 1 "$TOTAL"); do
    idx=$(( (i - 1) % n_asins ))
    ASIN="${ASINS[$idx]}"
    BATCH_ID=$(( 1000000 + i ))
    REQ_TS_HUMAN="$(date -u +%FT%TZ)"
    REQ_TS_EPOCH=$(date -u +%s)

    POST_RESP=$(curl -sS -m 30 -X POST "http://127.0.0.1:$PORT/scrape/batch" \
        -H "Authorization: Bearer $TOKEN" \
        -H 'Content-Type: application/json' \
        -d "{\"asins\":[\"$ASIN\"],\"batch_id\":$BATCH_ID}" 2>&1) || POST_RESP="curl_error"

    TASK_ID=$(printf '%s' "$POST_RESP" | python3 -c 'import json,sys
try:
    d=json.loads(sys.stdin.read())
    print(d.get("task_id",""))
except Exception:
    print("")' 2>/dev/null)

    if [ -z "$TASK_ID" ]; then
        printf '{"i":%d,"asin":"%s","batch_id":%d,"req_ts":"%s","status":"post_fail","resp":%s}\n' \
            "$i" "$ASIN" "$BATCH_ID" "$REQ_TS_HUMAN" \
            "$(printf '%s' "$POST_RESP" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()[:300]))')" \
            >> "$JSONL"
    else
        # Poll up to 10 min
        ST="timeout"
        for _ in $(seq 1 60); do
            STATUS_JSON=$(curl -sS -m 5 -H "Authorization: Bearer $TOKEN" \
                "http://127.0.0.1:$PORT/status/$TASK_ID" 2>/dev/null || echo '{}')
            ST=$(printf '%s' "$STATUS_JSON" | python3 -c 'import json,sys
try:
    d=json.loads(sys.stdin.read())
    print(d.get("status",""))
except Exception:
    print("")' 2>/dev/null)
            [ "$ST" = "completed" ] && break
            [ "$ST" = "failed" ] && break
            sleep 10
        done

        DONE_TS_HUMAN="$(date -u +%FT%TZ)"
        DONE_TS_EPOCH=$(date -u +%s)
        LATENCY=$(( DONE_TS_EPOCH - REQ_TS_EPOCH ))

        # Best-effort: read the checkpoint row to detect block / SG redirect.
        # last_error column carries `blocked_by_amazon` or other failure strings.
        CK_DETAIL=$(python3 - <<PYEOF 2>/dev/null || true
import json, os, sqlite3
db = os.path.join("$PROJECT", "scraper", "data", "checkpoints.db")
out = {"blocked": False, "sg_redirect": False, "result_excerpt": None}
try:
    conn = sqlite3.connect(db)
    conn.row_factory = sqlite3.Row
    row = conn.execute(
        "SELECT status, last_error, result_json FROM asin_progress WHERE batch_id=? AND asin=?",
        ($BATCH_ID, "$ASIN"),
    ).fetchone()
    if row:
        if row["last_error"] and "block" in row["last_error"].lower():
            out["blocked"] = True
        rj = row["result_json"]
        if rj:
            try:
                d = json.loads(rj)
                out["result_excerpt"] = {
                    k: (v[:80] if isinstance(v, str) else v)
                    for k, v in d.items() if k in ("title", "price", "brand", "category_name")
                }
                # SG-redirect heuristic: title or price hint at SGD or empty USD
                if isinstance(d.get("price"), (int, float)) and d.get("price") == 0.0 and d.get("title"):
                    out["sg_redirect"] = True
            except Exception:
                pass
    conn.close()
except Exception:
    pass
print(json.dumps(out))
PYEOF
)
        # Compose JSONL row
        printf '{"i":%d,"asin":"%s","batch_id":%d,"task_id":"%s","req_ts":"%s","done_ts":"%s","latency_s":%d,"status":"%s","detail":%s}\n' \
            "$i" "$ASIN" "$BATCH_ID" "$TASK_ID" "$REQ_TS_HUMAN" "$DONE_TS_HUMAN" \
            "$LATENCY" "$ST" "${CK_DETAIL:-{}}" >> "$JSONL"
    fi

    # Summarize incrementally so any reader gets a fresh-ish doc
    summarize "RUNNING"

    # Pace to next slot
    NEXT_T=$(( START_TS + i * INTERVAL_SEC ))
    NOW=$(date -u +%s)
    if [ "$NEXT_T" -gt "$NOW" ]; then
        sleep $(( NEXT_T - NOW ))
    fi
done

write_status "COMPLETED"
summarize "COMPLETED"
# trap EXIT will re-summarize and kill scraper
