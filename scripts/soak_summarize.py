#!/usr/bin/env python3
"""Summarize a soak-run JSONL log into the canonical Markdown report.

Idempotent: re-runs replace the file. Designed to be invoked from
soak_100_asin_24h.sh both at completion and from a SIGTERM/EXIT trap so
a partial run still produces a useful report.
"""
import argparse
import json
import os
from collections import Counter
from datetime import datetime, timezone


def _load_jsonl(path: str) -> list[dict]:
    rows = []
    if not os.path.exists(path):
        return rows
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return rows


def _read_status(path: str) -> str:
    try:
        with open(path) as fh:
            return fh.read().strip()
    except OSError:
        return "UNKNOWN"


def _percentile(values: list[float], p: float) -> float:
    if not values:
        return 0.0
    s = sorted(values)
    k = max(0, min(len(s) - 1, int(round(p * (len(s) - 1)))))
    return s[k]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--jsonl", required=True)
    ap.add_argument("--status", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--run-id", required=True)
    ap.add_argument("--total-target", type=int, default=100)
    args = ap.parse_args()

    status = _read_status(args.status)
    rows = _load_jsonl(args.jsonl)

    n_total = len(rows)
    statuses = Counter(r.get("status") for r in rows)
    completed = statuses.get("completed", 0)
    failed = statuses.get("failed", 0)
    post_fail = statuses.get("post_fail", 0)
    sg_redirect = sum(1 for r in rows if r.get("sg_redirect"))
    blocked = sum(1 for r in rows if r.get("blocked"))

    latencies = [
        r["latency_s"] for r in rows
        if isinstance(r.get("latency_s"), (int, float)) and r.get("status") == "completed"
    ]
    avg_lat = sum(latencies) / len(latencies) if latencies else 0.0
    p50 = _percentile(latencies, 0.50)
    p95 = _percentile(latencies, 0.95)
    p99 = _percentile(latencies, 0.99)

    asin_results: dict[str, list[str]] = {}
    for r in rows:
        a = r.get("asin", "?")
        s = r.get("status", "?")
        asin_results.setdefault(a, []).append(s)

    # First/last timestamps
    first_ts = rows[0].get("req_ts") if rows else "(none)"
    last_ts = rows[-1].get("done_ts") or rows[-1].get("req_ts") if rows else "(none)"

    md_lines = [
        f"# 100-ASIN 24h Soak Test — Run `{args.run_id}`",
        "",
        f"**Status**: `{status}`",
        f"**Run ID**: `{args.run_id}`",
        f"**JSONL log**: `{args.jsonl}`",
        f"**Mode**: real (`MOCK_EXTERNAL_APIS=false`), DIRECT-only (no DECODO/SMART)",
        f"**First fetch**: {first_ts}",
        f"**Last fetch**: {last_ts}",
        f"**Generated**: {datetime.now(timezone.utc).isoformat()}",
        "",
        "## Why this report exists",
        "",
        "Validates R-CARRY-13 from `docs/scraper-multi-review-2026-05-01.md`: "
        "can the scraper run for 24h without Amazon CAPTCHA blocks emerging? "
        "Soak runs DIRECT-only because DECODO/SMARTPROXY env vars aren't set "
        "in this environment — so this answers a narrower question: "
        "**without a paid proxy, can we sustain 100 fetches/24h from this server?**",
        "",
        "## Summary",
        "",
        f"- Fetches attempted: **{n_total} / {args.total_target}**",
        f"- `completed`: **{completed}** ({completed*100/max(n_total,1):.1f}%)",
        f"- `failed`: **{failed}** ({failed*100/max(n_total,1):.1f}%)",
        f"- `post_fail` (POST never returned task_id): **{post_fail}**",
        f"- Detected blocked (CAPTCHA pattern): **{blocked}**",
        f"- Detected geo-redirected to amazon.sg: **{sg_redirect}**",
        "",
        "## Latency (status=completed only)",
        "",
        "| Metric | Seconds |",
        "|--------|---------|",
        f"| min | {min(latencies, default=0):.1f} |",
        f"| avg | {avg_lat:.1f} |",
        f"| p50 | {p50:.1f} |",
        f"| p95 | {p95:.1f} |",
        f"| p99 | {p99:.1f} |",
        f"| max | {max(latencies, default=0):.1f} |",
        "",
        "## Per-ASIN result distribution",
        "",
        "| ASIN | n | completed | failed | post_fail |",
        "|------|---|-----------|--------|-----------|",
    ]
    for asin, rs in sorted(asin_results.items()):
        c = Counter(rs)
        md_lines.append(
            f"| `{asin}` | {len(rs)} | {c.get('completed', 0)} | "
            f"{c.get('failed', 0)} | {c.get('post_fail', 0)} |"
        )

    md_lines += [
        "",
        "## Block analysis",
        "",
        "`worker_pool._is_blocked` matches Amazon CAPTCHA / robot-check phrases. "
        "Geo-redirect to amazon.sg is *not* a block — the SG store renders normally, "
        "just with SGD prices. So **block count is the canonical 'we got banned' signal**, "
        "while **sg_redirect count signals data quality (USD prices missing)**.",
        "",
        "## Caveats",
        "",
        "- Single OCI Asia IP — not generalizable to a fleet.",
        "- DIRECT only. The PR2 proxy threading fix means that *with* DECODO/SMARTPROXY "
        "  env vars set, this same soak would test the full M9 architecture.",
        "- Pacing ~14 min/fetch is conservative; aggressive 5K/day soak (still TODO) "
        "  would push different limits.",
        "- Scrapling 0.4.2 stealth defaults; no custom warmup beyond US zip cookie.",
        "",
        "## Next",
        "",
        "When this finishes, JKI-86 (3-channel benchmark) is the natural follow-up:",
        "set `DECODO_PROXY_URL`/`SMARTPROXY_URL` and re-run with `PROXY_RATIO=5:2.5:2.5` "
        "to compare proxy vs direct block rates side by side.",
        "",
        "---",
        "",
        f"_Auto-generated by `scripts/soak_summarize.py` from `{args.jsonl}`._",
    ]

    with open(args.output, "w") as fh:
        fh.write("\n".join(md_lines) + "\n")
    print(f"wrote {args.output} ({len(rows)} rows summarized, status={status})")


if __name__ == "__main__":
    main()
