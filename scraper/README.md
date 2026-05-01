# scraper — Amazon product scraper microservice

FastAPI service on port **3211**. Scrapes Amazon product pages with
Scrapling (Camoufox) stealth browser, 3-channel proxy rotation,
checkpoint/resume, and durable Rails handoff.

## Quick start

```bash
# 1. Python 3.12+ venv (Scrapling 0.4.x requires Py 3.10+; PyPI does not
#    ship 0.4.2 for Python 3.9). The repo ships scraper/.venv pre-built.
python3.12 -m venv scraper/.venv      # only if .venv is missing
scraper/.venv/bin/pip install -r scraper/requirements.txt
scraper/.venv/bin/scrapling install   # browser binaries (one-time, ~150MB)

# 2. Env. Mock mode requires only the token; real mode needs proxies.
cp .env.example .env
# Edit .env — at minimum set SCRAPER_API_TOKEN (Rails uses the same value
# to authenticate /api/products/batch_upsert ← scraper).

# 3. Run with foreman (Rails + Tailwind + Jobs + scraper together)
bin/dev       # all four processes; scraper at 127.0.0.1:3211
# OR scraper standalone:
cd scraper && .venv/bin/python -m uvicorn main:app --host 127.0.0.1 --port 3211 --reload

# 4. Verify
curl http://127.0.0.1:3211/health        # public, returns {"status":"ok"}
curl -H "Authorization: Bearer $SCRAPER_API_TOKEN" http://127.0.0.1:3211/readyz
```

## Endpoints

All mutating + data-disclosing endpoints require `Authorization: Bearer $SCRAPER_API_TOKEN`. `/health` is public.

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| `GET` | `/health` | public | Liveness — `{"status":"ok"}` |
| `GET` | `/readyz` | bearer | Readiness — version, browser session, worker pool |
| `POST` | `/scrape` | bearer | Legacy single-batch scrape (delegates to `/scrape/batch`) |
| `POST` | `/scrape/batch` | bearer | 3-channel batch with WorkerPool + CheckpointManager |
| `GET` | `/checkpoint/{batch_id}/remaining` | bearer | Resume support — pending/scraped ASINs |
| `GET` | `/status/{task_id}` | bearer | Task status |
| `PUT` | `/config/proxy-ratio` | bearer | Hot-reconfigure channel weights (5:2.5:2.5 default) |
| `PUT` | `/config/batch-size` | bearer | Hot-reconfigure per-channel batch sizes |
| `GET` | `/config/proxy-status` | bearer | Per-channel health + worker pool stats |
| `POST` | `/collect/bsr` | bearer | Best Sellers list scrape |
| `POST` | `/collect/movers` | bearer | Movers & Shakers scrape |
| `POST` | `/collect/urls` | bearer | Bulk ASIN URL collection |
| `POST` | `/collect/trends` | bearer | Google Trends |
| `POST` | `/collect/social` | bearer | Reddit signals |
| `POST` | `/resync/price` | bearer | Re-scrape product prices |

OpenAPI/Swagger UI: `http://127.0.0.1:3211/docs`

## Curl examples

```bash
TOK=$SCRAPER_API_TOKEN

# Queue a batch
curl -X POST http://127.0.0.1:3211/scrape/batch \
     -H "Authorization: Bearer $TOK" \
     -H "Content-Type: application/json" \
     -d '{"asins":["B0BSHF7WHW","B09B8V1LZ3"],"batch_id":42,"daily_limit":5000}'
# → {"task_id":"...","batch_id":42,"total_queued":2,"channel_distribution":{...}}

# Poll status
curl -H "Authorization: Bearer $TOK" http://127.0.0.1:3211/status/<task_id>

# Get remaining for resume
curl -H "Authorization: Bearer $TOK" http://127.0.0.1:3211/checkpoint/42/remaining

# Hot-reconfigure proxy ratio (no restart)
curl -X PUT http://127.0.0.1:3211/config/proxy-ratio \
     -H "Authorization: Bearer $TOK" \
     -H "Content-Type: application/json" \
     -d '{"direct":7,"decodo":2,"smart":1}'
```

## Environment variables

See [`.env.example`](../.env.example). Quick reference for the M9 50K
variables (most have safe defaults — only `SCRAPER_API_TOKEN`,
`DECODO_PROXY_URL`, and `SMARTPROXY_URL` typically need to be set):

| Variable | Default | Purpose |
|----------|---------|---------|
| `SCRAPER_API_TOKEN` | (required) | Bearer token for /scrape* /config* /collect* /readyz |
| `MOCK_EXTERNAL_APIS` | `true` | Skip real fetch; return canned responses |
| `SCRAPER_PORT` | `3211` | uvicorn bind port |
| `SCRAPER_WORKERS` | `3` | Concurrent stealth workers in WorkerPool |
| `PROXY_RATIO` | `5:2.5:2.5` | direct:decodo:smart channel weights |
| `DECODO_PROXY_URL` | (unset → channel disabled) | DECODO residential proxy URL |
| `SMARTPROXY_URL` | (unset → channel disabled) | SmartProxy URL |
| `DIRECT_BATCH_SIZE` | `500` | Per-channel batch chunking (override `CHANNEL_BATCH_SIZE`) |
| `DECODO_BATCH_SIZE` | `500` | — |
| `SMART_BATCH_SIZE` | `500` | — |
| `CHANNEL_BATCH_SIZE` | `500` | Default per-channel batch size |
| `BROWSER_MAX_PAGES` | `3` | Concurrent pages per AsyncStealthySession |
| `SESSION_MAX_FETCHES` | `100` | Fingerprint TTL — recreate session every N fetches |
| `AMAZON_ZIP_CODE` | `90006` | US delivery zip for geo cookie |
| `BATCH_RESULT_SIZE` | `50` | BatchResultBuffer flush threshold |
| `BATCH_FLUSH_INTERVAL` | `30.0` | Periodic flush interval (seconds) |
| `RAILS_BATCH_ENDPOINT` | `http://localhost:3210/api/products/batch_upsert` | Rails durability sink |
| `WORKER_MEMORY_LIMIT_MB` | (default in MemoryWatchdog) | RSS threshold for drain-restart |

## Architecture

- **3-channel proxy** — `ProxyRotator` distributes ASINs by weight across DIRECT / DECODO / SMARTPROXY. Hot-reconfigurable via `/config/proxy-ratio`.
- **Per-channel queues** — Each worker pops only from its channel's queue. Cross-channel work is impossible by construction.
- **Ban handling** — On CAPTCHA/block detection, `_handle_ban` drains the banned channel's queue and redistributes (incl. the in-flight ASIN) to healthy channels weighted by their config.
- **Two-phase checkpoint** — `pending → scraped → persisted`. Rails confirmation transitions `scraped → persisted` via callback; a Rails outage during a batch is replayed on resume (no silent data loss).
- **WAL SQLite** — `scraper/data/checkpoints.db`. WAL + index for concurrent worker writes.
- **Replay tool** — `scripts/replay_fallback.py` resends `scraper/data/fallback_*.json` when Rails comes back. Idempotent — skips items already persisted in the checkpoint.
- **Memory watchdog** — Drain-restart on RSS threshold to prevent OOM on long-running 50K batches.

## Operational

```bash
# Replay fallbacks after a Rails outage
SCRAPER_API_TOKEN=... scraper/.venv/bin/python scripts/replay_fallback.py --dry-run
SCRAPER_API_TOKEN=... scraper/.venv/bin/python scripts/replay_fallback.py
# (drops fallback files on success unless --keep-on-success)

# Check who's queued where
curl -H "Authorization: Bearer $TOK" http://127.0.0.1:3211/config/proxy-status \
  | jq '.worker_pool.queues_per_channel'
```

## Known issues

- **Geo-redirect** — without a US proxy, OCI Asia IP redirects ASINs to `amazon.sg`. Set `DECODO_PROXY_URL` or `SMARTPROXY_URL` for production.
- **Volume zero-block validation** — 100-ASIN 24h soak still pending (R-CARRY-13). Required before declaring 50K production-ready.
- **Rails Oracle ADB cert** — wallet may need renewal (ORA-29024); see `mcp-sqlcl-wallet-cache-renewal` skill.

## See also

- `docs/scraper-multi-review-2026-05-01.md` — full 5-skill audit
- `docs/scraper-p0-fixes-2026-05-01.md` — JKI-98 P0 fix report
- `docs/scraper-p1-fixes-2026-05-01.md` — JKI-99 P1 fix report (PR4+PR5)
