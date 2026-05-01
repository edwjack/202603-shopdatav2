# Scraper A 5-Skill 통합 리뷰 (2026-05-01)

**대상**: `scraper/*.py` (11파일, FastAPI :3211) + `app/controllers/api/products_controller.rb` (Rails consumer)
**기준 commit**: `3f24372` (2026-04-07 M9 50K 50K-scale 도입)
**검토 5종**: `/review` `/codex` `/browse` `/devex-review` `/qa`
**오케스트레이션**: Claude 주관, Codex 가 각 게이트에서 사용자 대리 검토 (verdict-only short prompt + stdin redirect)
**Gate 결과**: Gate 1 PASS (high reasoning, 600s) — proceed-to-report

## 30초 요약 (TL;DR)

3f24372 commit 의 M9 50K 아키텍처는 **현재 상태로 운영 불가**. 발견 5종이 일관되게 가리키는 문제:

1. **D1 — 서비스 자체가 부팅 안 됨** (`rate_limiter.py:11` 잘못된 import) — Procfile.dev 명령으로 즉시 ImportError. 3주 전 commit 이후 누구도 라이브 서비스 띄운 적 없을 가능성.
2. **C1/F1 — 3채널 프록시가 실제 fetch 에 적용 안 됨** (`worker_pool.py:257`) — 프록시 비용 절감 메커니즘이 코드상 무력. 모든 워커가 DIRECT 로 나가면서 metrics 만 채널별로 기록.
3. **F5 — 체크포인트가 Rails 영속화 전에 success 마킹** (`worker_pool.py:339` ↔ `result_buffer.py:178`) — flush 모두 실패하면 fallback 파일로만 남고 SQLite 는 completed → 다음 resume 시 그 ASIN 스킵 → **silent data loss**. 50K 운영의 데이터 무결성 위협.

**Gate 1 의 MUST-NOT-MISS 3종**: D1 boot, C1 proxy bypass, F5 durability gap.

## 5-Skill 결과 매트릭스

| 발견 | /review | /codex | /browse | /devex | /qa |
|------|---------|--------|---------|--------|-----|
| Proxy/profile 미적용 (CRIT) | C1 ✅ | F1 ✅ | — | — | (mock 검증 불가) |
| 모든 endpoint 인증 부재 (CRIT) | C2 ✅ | F9 ✅ | (관찰) ✅ | — | Q1 ✅ live |
| Service 부팅 불가 (CRIT) | — | — | — | D1 ✅ | T1 (live 검증) |
| Checkpoint→Rails durability gap (CRIT) | — | F5 ✅ | — | — | (mock 검증 불가) |
| Retry-3 limit 미작동 (HIGH) | C3 ✅ | F6 ✅ (확장) | — | — | — |
| Concurrent batch shared queue (HIGH) | — | F4 ✅ | — | — | T18 (race 의심) |
| Worker queue cross-channel (HIGH) | — | F2 ✅ | — | — | — |
| Ban → redistribute_from 미호출 (HIGH) | — | F3 ✅ | — | — | — |
| Flush lock blocks workers (HIGH) | H2 ✅ | F8 ✅ | — | — | — |
| Rails sanitize nested 누락 (HIGH) | H3 ✅ | F10 ✅ | — | — | Q5 ✅ live |
| SQLite no WAL (HIGH) | H4 ✅ | — | — | — | — |
| tasks dict no lock (HIGH) | H1 ✅ | — | — | — | — |
| Pydantic Field 제약 부재 (P1) | — | F9 ⊆ | (관찰) | D5 ✅ | Q2,Q3,Q4 ✅ live |
| README 부재 (P1) | — | — | — | D3 ✅ | — |
| requirements.txt 깨짐 (P1) | — | — | — | D2 ✅ | — |
| .env.example M9 변수 누락 (P1) | — | — | — | D4 ✅ | — |
| /docs Swagger 메타 빈약 (P1) | — | — | ✅ | D5,D6 ✅ | — |
| 50 동시 호출 무제한 (P2) | — | — | — | — | Q6 ✅ live |
| /collect/* 200+error (P2) | M2 ✅ | — | (관찰) | D7 ✅ | Q8 ✅ live |
| /health 빈약 (P2) | M3 ✅ | — | — | D9 ✅ | Q9 ✅ live |

5중 확인된 항목 = 0. 3중 = 1 (auth 부재). 2중 = 8 (대부분 CRIT/HIGH).
**일관성 PASS** — Gate 1 calibration verdict 일치.

## P0 (즉시 fix, 운영 차단)

### P0-1 — Service boot 복구 (D1)
**파일/라인**: `scraper/rate_limiter.py:11`
```python
# AS-IS
from scraper.config import RATE_LIMITS
# TO-BE
from config import RATE_LIMITS
```
또는 `scraper/__init__.py` 추가 + `Procfile.dev` 의 scraper 라인을 `python -m uvicorn scraper.main:app`(project root cwd) 로 수정.

**검증**: `cd scraper && .venv/bin/python -m uvicorn main:app --port 3211` 가 "Application startup complete." 까지 진행.

### P0-2 — Proxy/profile 실제 적용 (C1, F1)
**파일/라인**: `scraper/worker_pool.py:257`, `scraper/session_manager.py:24-30`
```python
# 현재 (로깅만, 적용 안 됨)
proxy = self.proxy_rotator.get_proxy(worker.channel)
worker.session = SessionManager()  # proxy 무시!

# 수정
worker.session = SessionManager(proxy=proxy, profile=worker.profile)
# SessionManager.start() 에서 AsyncStealthySession(proxy=proxy, ...) 전달
```
**검증**: 로그에 `BANNED_BY_AMAZON` 빈도 확인 — 현재 모두 DIRECT 라 비례 분포 안 됨. 수정 후 채널별 stats 의 fail_count 가 차등화.

### P0-3 — Checkpoint vs Rails persistence durability (F5, C3 일부)
**파일/라인**: `scraper/worker_pool.py:335-339`, `scraper/result_buffer.py:168-178`
```python
# 현재
self.checkpoint.mark_completed(batch_id, asin, data)  # SQLite 완료
await self.result_buffer.add(data)                    # Rails flush — 실패 가능
# fallback file 만 남으면 다음 resume 에서 스킵

# 수정 (단계적 status)
self.checkpoint.mark_scraped(batch_id, asin, data)    # status='scraped'
await self.result_buffer.add(data)                    # 비동기 큐잉
# result_buffer 가 Rails 응답 200 수신 시 mark_persisted 콜백
# 'scraped' 상태는 resume 시 재시도 (fallback 파일도 replay)
```
**검증**: Rails 다운 → 1K ASIN scrape → restart → 데이터 누락 0건.

### P0-4 — Auth on scraper control endpoints (C2, F9, Q1)
**파일/라인**: `scraper/main.py:322-572`
```python
# 신규 dependency
def verify_token(authorization: str = Header(None)):
    expected = os.environ.get("SCRAPER_API_TOKEN")
    if not expected:
        raise HTTPException(503, "Server not configured")
    token = (authorization or "").removeprefix("Bearer ").strip()
    if not token or not secrets.compare_digest(token, expected):
        raise HTTPException(401, "Invalid token")

# 적용
@app.post("/scrape/batch", dependencies=[Depends(verify_token)])
@app.put("/config/proxy-ratio", dependencies=[Depends(verify_token)])
# 등
```
Rails 측은 이미 SCRAPER_API_TOKEN 검증함 (products_controller.rb:31-36) — scraper 도 같은 토큰 재사용.

**검증**: T8/T11 의 무인증 호출이 401 로 변경.

## P1 (1주일 내, 데이터 품질·DX)

### P1-1 — Pydantic 입력 제약 (Q2, Q3, Q4, F9, D5)
```python
from pydantic import Field, field_validator

class BatchScrapeRequest(BaseModel):
    asins: list[str] = Field(min_length=1, max_length=10000)
    batch_id: int = Field(gt=0)
    daily_limit: int = Field(default=5000, gt=0, le=100000)

    @field_validator("asins")
    @classmethod
    def validate_asin_format(cls, v):
        bad = [a for a in v if not re.fullmatch(r"^[A-Z0-9]{10}$", a)]
        if bad:
            raise ValueError(f"invalid asin: {bad[:5]}")
        return v

class ProxyRatioRequest(BaseModel):
    direct: float = Field(default=5, ge=0, le=100)
    decodo: float = Field(default=2.5, ge=0, le=100)
    smart: float = Field(default=2.5, ge=0, le=100)
```

### P1-2 — Concurrent batch isolation (F4)
**파일**: `scraper/worker_pool.py:188-239`
- `_task_queue` 를 batch 별 분리 또는 `run_batch` 호출을 직렬화 (asyncio.Lock).
- 권장: `BatchExecutor` 클래스 분리, batch 마다 fresh queue + worker subset.

### P1-3 — Ban → redistribute_from 호출 (F3)
**파일**: `scraper/worker_pool.py:325-330`
```python
if self._is_blocked(html):
    self.rate_limiter.record_failure(channel, is_ban=True)
    self.proxy_rotator.record_failure(channel, is_ban=True)
    # 신규: 큐의 잔여 ASIN 을 healthy 채널로 이전 + 재큐잉
    new_dist = self.proxy_rotator.redistribute_from(channel)
    await self._requeue(new_dist, batch_id)
    self.checkpoint.mark_failed(batch_id, asin, "blocked_by_amazon")
    return
```

### P1-4 — checkpoint status='failed' 마킹 + WAL (C3, F6, H4)
**파일**: `scraper/checkpoint.py`
```python
# _init_schema 에 추가
self._conn.execute("PRAGMA journal_mode=WAL")
self._conn.execute("PRAGMA synchronous=NORMAL")

# mark_failed 수정
def mark_failed(self, batch_id, asin, error):
    with self._lock, self._conn:
        # attempts ++ 후 status 변경
        self._conn.execute(
            "UPDATE asin_progress SET attempts = attempts + 1, last_error=?, "
            "status = CASE WHEN attempts + 1 >= 3 THEN 'failed' ELSE 'pending' END, "
            "updated_at=? WHERE batch_id=? AND asin=?",
            (error, now, batch_id, asin),
        )
```

### P1-5 — Rails strong params + nested sanitize (H3, F10, Q5)
**파일**: `app/controllers/api/products_controller.rb`
```ruby
def permitted_product_params(data)
  cleaned = data.permit(
    :asin, :title, :price, :brand,
    :review_rating, :review_count, :category_name,
    about_this: [], tags: [],
    images: [[:hiRes, :variant]],
    overview: [[:key, :value]],
    options: {},
    quantity: {}
  )
  recursive_sanitize(cleaned.to_h)
end

def recursive_sanitize(obj)
  case obj
  when String then ActionController::Base.helpers.sanitize(obj)
  when Hash   then obj.transform_values { |v| recursive_sanitize(v) }
  when Array  then obj.map { |v| recursive_sanitize(v) }
  else obj
  end
end

def batch_upsert
  validate_payload!  # asins 형식, 길이 제한
  # ...
end
```

### P1-6 — Result buffer flush lock 해제 (H2, F8)
**파일**: `scraper/result_buffer.py:55-110, 133-166`
```python
async def _do_flush(self):
    # 락 안에서는 buffer swap 만
    async with self._lock:
        if not self.buffer:
            return
        batch = self.buffer
        self.buffer = []
        self._batch_counter += 1
    # 락 풀고 HTTP I/O
    await self._http_post_with_retries(batch)
```

### P1-7 — DX 필수 (D2, D3, D4)
- `scraper/README.md` 신설 (env 표 + curl 예시)
- `requirements.txt` 의 scrapling 핀을 정확한 버전 또는 git URL 명시
- `.env.example` 에 M9 변수 18종 추가

## P2 (월 내, 운영 품질)

| ID | 항목 | 비용 |
|----|------|------|
| P2-1 | /docs 메타 (tags, response_model, status_code, Field, 12 docstring) | 4-6h |
| P2-2 | /scrape 동시성 cap (rate-limit middleware 또는 token bucket) | 2h |
| P2-3 | /collect/* 응답을 4xx/5xx 통일 | 2h |
| P2-4 | /health 가 Rails reachability + WorkerPool/Checkpoint health 포함, /readyz /livez 분리 | 2h |
| P2-5 | tasks dict 에 asyncio.Lock 또는 collections-safe 구조 | 1h |
| P2-6 | Periodic_flush 무한 루프에 fault path | 30m |
| P2-7 | /health version 5.0.0 통일 + /metrics endpoint | 1h |

## Risk 분석표

| ID | Risk | 영향 영역 | Likelihood | Impact | Mitigation |
|----|------|----------|------------|--------|-----------|
| R1 | **D1 미해결로 50K 본작업 시작 자체가 불가** | 일정/계획 | High | High | P0-1 5분 fix. 이후 Procfile.dev 로 라이브 부팅 검증을 CI 또는 PROGRESS.md 기준에 포함 |
| R2 | **C1/F1 proxy bypass 로 비용 절감 효과 0** | 비용 절감 ROI | High | High | P0-2 fix 후 채널별 success/fail 분리 통계로 검증. 미해결 시 이전 유료 tool 대비 절감 0. |
| R3 | **F5 silent data loss** — 무결성 깨짐 | 데이터 품질 | High | Critical | P0-3 단계적 status 도입. 100-ASIN 부하 + Rails 의도적 down 시뮬레이션으로 회귀 테스트 |
| R4 | **C2/F9 unauth — 동일 호스트 다른 프로세스가 비용 조작 가능** | 보안/비용 | Medium | High | P0-4 token 적용. /config/* 는 SCRAPER_API_TOKEN 필수. 운영 시 host bind 도 unix socket 검토 |
| R5 | **F4 concurrent /scrape/batch 두 번째 호출이 첫 batch 와 race** | 운영 | Medium | High | Solid Queue cron 이 동시 호출 시 발생. P1-2 직렬화 우선. |
| R6 | **C3/F6 retry 한도 미작동 → 영원히 실패 ASIN 재시도** | 진행 진척 | High | Medium | P1-4 status='failed' 마킹. checkpoint cleanup 룰 추가 (>30일 실패 ASIN 정리) |
| R7 | **F3 ban 발생 시 잔여 작업 먹통** | 50K 일정 | Medium | High | P1-3 redistribute_from 호출. 실시간 채널 health 모니터링 (/config/proxy-status 폴링) |
| R8 | **H4 SQLite 단일 lock — 50K 부하 시 직렬화** | 처리량 | Medium | Medium | P1-4 의 PRAGMA journal_mode=WAL. 부하 1K → 5K → 10K 스테이지 검증 |
| R9 | **H3/Q5 Rails sanitize 우회로 nested XSS** | 보안 | Low | High | P1-5 recursive_sanitize. CSP 헤더 + 뷰에서 raw HTML 출력 패턴 점검 |
| R10 | **Q2-Q4 무한대/음수/거대 size 가 Pydantic 통과** | 데이터 폴루션, DoS | Medium | Medium | P1-1 Field 제약. WAF 또는 nginx 단 size limit 보조 |
| R11 | **D2 requirements.txt 깨짐 — 새 환경에서 재설치 불가** | 재현성/이전성 | High | Medium | P1-7 정확한 핀 또는 git URL. CI 에서 fresh venv pip install 검증 |
| R12 | **D3-D6 README/docstring/Field 부재 — DX 점수 2.3/10** | 신규 개발자 합류 | Medium | Medium | P1-7 README + P2-1 OpenAPI 메타. /docs Swagger 가 SDK 자동 생성에도 사용됨 |
| R13 | **mock-mode 한정 검증으로 라이브 50K 회귀 미검증** | 본 리포트 신뢰도 | High | Medium | 50-ASIN 24h soak (PROGRESS.md M9 TODO) 우선. 본 리포트는 정적 + mock 검증 한계 명시 |
| R14 | **fallback 파일이 쌓이면 디스크 차오름** | 운영 | Low | Medium | result_buffer.fallback dir 의 cron 정리. 알람 설정 |
| R15 | **R3 fix 후 fallback 재처리 메커니즘 없음** | 데이터 무결성 | Medium | Medium | replay 도구 작성 (`scripts/replay_fallback.py`) — fallback_*.json 을 Rails 에 재전송 |

## 권장 순서 (실행 가능한 PR 단위)

| Sprint | PR | 포함 항목 | 추정 소요 |
|--------|-----|-----------|-----------|
| 즉시 | PR1 hot-fix | P0-1 (boot fix) | 30분 + 검증 |
| 1일 | PR2 P0 코어 | P0-2 (proxy 적용), P0-4 (auth) | 0.5일 + 라이브 mock 검증 |
| 2-3일 | PR3 데이터 무결성 | P0-3 (durability), P1-4 (status), P1-3 (ban redistribute) | 1.5일 + 부하 시뮬 |
| 4-5일 | PR4 동시성/검증 | P1-1 (Pydantic), P1-2 (batch isolation), P1-6 (flush lock) | 1일 |
| 6-7일 | PR5 Rails | P1-5 (sanitize) | 0.5일 |
| 8-10일 | PR6 DX | P1-7 (README/.env/requirements) + P2-1 (OpenAPI) | 1일 |
| 운영 시 | PR7 모니터링 | P2-4 (/health) + P2-7 (/metrics) | 0.5일 |

총: ~6 영업일 (R3 100-ASIN soak 검증 별도 24h)

## 미검증 영역 (시간 부족, 본 리포트 caveat)

- **라이브 50K reliability** — mock 모드 한정 검증. 100-ASIN 24h soak (PROGRESS.md M9 TODO) 가 R3, R13 해결의 전제.
- **실제 amazon.com fetch 시 stealth profile 적용 효과** — codex F1 문제 fix 후 차단율 측정 필요.
- **SQLite WAL + 동시 5000 write 부하 한계** — 부하 테스트 별도.
- **fallback 파일 → Rails 재전송 도구** — 미존재, 작성 필요 (R15).

## 검토 절차 메타데이터

| Stage | Reasoning | Time | Tokens | Verdict |
|-------|-----------|------|--------|---------|
| /codex (background) | high | ~600s | 24,656 | 10 finding 산출 |
| Gate 1 | high | ~120s | 3,153 | PASS, proceed-to-report |
| Gate 2 | (예정) | — | — | — |

산출물:
- 발견 raw: `/tmp/review-cmp/findings/{review,codex,browse,devex-review,qa}.md` + `codex_review.txt`
- scraper 임시 패치: `rate_limiter.py:11` (검증 후 PR 로 정식 fix 필요)
- live test logs: `/tmp/review-cmp/scraper.log`, `scraper-fg.log`
