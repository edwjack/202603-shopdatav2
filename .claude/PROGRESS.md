# Progress Tracking - shopdatav2

**Project**: 202603-shopdatav2
**Created**: 2026-02-21
**Last Updated**: 2026-05-01

---

## Current Status

| Milestone | Status | Date | Summary |
|-----------|--------|------|---------|
| M1 Foundation | COMPLETE | 2026-02-21 | rbenv, Ruby 3.3.10, Oracle IC, Rails 8.0.4, Multi-DB, Puma 3170 |
| M2 Schema+Seeds | COMPLETE | 2026-02-21 | 8 tables, vector indexes, seed data |
| M3 Dashboard | COMPLETE | 2026-02-22 | Sidebar layout, dashboard, categories, recommendations, products, 6 Stimulus controllers |
| M4 Collectors | COMPLETE | 2026-02-22 | 5 collector jobs, 6 services, 5 JSON fixtures, jobs status page |
| M5 AI Analysis | COMPLETE | 2026-02-23 | CategoryAnalyzerJob, WeeklyRecommendationDigestJob, ClaudeApiService, VectorSearchService |
| M6 Sourcing Pipeline | COMPLETE | 2026-02-23 | 5-phase pipeline, 6 services, 4 jobs, 3 sync schedules, 61 tests |
| M7 Scrapling+Shopify | COMPLETE | 2026-03-10 | 4-phase pipeline, Shopify GraphQL, 3 Shopify services, 82 tests/206 assertions |
| M8 Polish | COMPLETE | 2026-03-10 | Dead code cleanup, validations, dashboard enhancement, pagination, UX polish |
| **M9 50K Scale** | **IN PROGRESS** | 2026-04-07 | 3-channel proxy, WorkerPool, checkpoint/resume, adaptive rate limiting, Shopify mapper |

**Test Suite**: 88 runs, 219 assertions, 0 failures, 0 errors
**Brakeman**: 0 warnings
**Routes**: 31

---

## M9 50K Scale Architecture (2026-04-07)

### What was built
- **3-channel proxy system** (DIRECT/DECODO/SMARTPROXY) with configurable ratio (5:2.5:2.5)
- **WorkerPool** with N concurrent browser sessions + stealth profiles (viewport/locale/timezone/UA)
- **AdaptiveRateLimiter** per-channel delay adjustment (success→speedup, block→slowdown)
- **CheckpointManager** SQLite-based cross-day resume via batch_id correlation
- **BatchResultBuffer** accumulates results, pushes to Rails in batches of 50
- **MemoryWatchdog** RSS monitoring with drain-restart on threshold
- **DailyQuotaManager** 5K/day cap + Solid Queue cron trigger
- **Rails batch_upsert** token-authenticated bulk product endpoint
- **ShopifyMapper** transforms scraped data to Shopify Admin API format
- **Benchmark tool** 3-channel performance comparison with Shopify export

### New files (12)
```
scraper/proxy_rotator.py        scraper/worker_pool.py
scraper/rate_limiter.py         scraper/result_buffer.py
scraper/checkpoint.py           scraper/shopify_mapper.py
scraper/memory_watchdog.py      scraper/benchmark.py
app/controllers/api/products_controller.rb
app/jobs/scrape_batch_job.rb
app/services/daily_quota_manager.rb
```

### Modified files (8)
```
scraper/main.py (v4→v5)        scraper/config.py (3-channel vars)
scraper/session_manager.py     scraper/parsers/product_page.py
scraper/requirements.txt       config/routes.rb
config/recurring.yml           app/jobs/sourcing_pipeline_job.rb
.gitignore
```

### New API Endpoints
```
POST /scrape/batch              GET  /checkpoint/{id}/remaining
PUT  /config/proxy-ratio        PUT  /config/batch-size
GET  /config/proxy-status       POST /api/products/batch_upsert
```

### Benchmark results (DIRECT channel, 10 non-gated products)
- Success: 10/10 (100%), 0 blocks
- Throughput: 141/hr, avg 7.2s/request
- Data quality: Title 90%, Price 90%, Brand 90%, Image 90%

### Code review fixes applied
- P0: SQLite threading.Lock on all CheckpointManager operations
- P0: palette_counter race condition (moved to per-worker state)
- P0: Auth bypass when SCRAPER_API_TOKEN unset
- P1: ASIN regex validation before URL interpolation
- P1: JSON key mismatch in DailyQuotaManager (asins→remaining_asins)
- P1: CheckpointManager.close() in lifespan teardown

### Known issues
- Geo-redirect: OCI Asia IP → some ASINs redirect to amazon.sg (US proxy resolves)
- Overview parser: spec table name/value empty (parser improvement needed)
- Price $0 on "See all buying options" products (rare in $30-80 range)

### TODO
- [x] ~~**P0 — PR1 hot-fix**: rate_limiter.py:11 `from scraper.config` → `from config` (D1 boot 차단)~~ (657d0c9 2026-05-01)
- [x] ~~**P0 — PR2 proxy+auth**: SessionManager 에 proxy/profile 전달 (C1/F1), control endpoint 토큰 인증 (C2/F9/Q1)~~ (81d0d7c+1a21df7 2026-05-01)
- [x] ~~**P0 — PR3 durability**: checkpoint 단계적 status (scraped→persisted), retry status='failed' 마킹, fallback replay 도구 (F5/C3/F6/R15)~~ (8d1c6e0+1965f6e 2026-05-01)
- [x] ~~**P1 — PR4 동시성**: Pydantic Field 제약, batch isolation (F4), flush lock 해제 (H2/F8), ban → redistribute (F3)~~ (7934ea7 + 231c554 + ec87ddc + ac66916, 2026-05-01) — Pydantic Field 는 PR2 에서 처리, F8/H2 flush lock 은 PR3 에서 처리
- [x] ~~**P1 — PR5 Rails**: recursive_sanitize, batch_upsert 입력 검증 (H3/F10/Q5)~~ (6537647 + 91d62aa, 2026-05-01)
- [x] ~~**P1 — PR6 DX**: scraper/README.md, .env.example 에 M9 변수 18종, requirements.txt scrapling 핀 정확화 (D2-D4)~~ (7ef7663 + 36cc34c, 2026-05-01)
- [x] ~~**P2 — PR7 monitoring**: /docs OpenAPI 메타 (tags/Field/docstring)~~ (f9d50c6, 2026-05-01) — /health Rails reachability + /metrics endpoint 는 별도 후속 PR
- [ ] Configure DECODO_PROXY_URL and SMARTPROXY_URL for multi-channel testing
- [ ] Overview parser improvement (spec table extraction)
- [ ] 50-ASIN full benchmark with all 3 channels (Risk R1·R3 — stale benchmark 갱신)
- [ ] 100-ASIN 24h soak test with DIRECT only — zero-block 가능성 증명 (Risk R3·R7·R13)
- [ ] Staged load test 1K→5K→10K→50K + checkpoint kill-recovery 시뮬레이션 (Risk R12)
- [ ] DECODO/SMARTPROXY 견적 → 50K 트래픽 단가 산출 → 이전 유료 tool 비용 breakeven (Risk R11)
- [ ] Unit tests for new modules (35 tests planned)
- [ ] Jina fallback adapter (dead-ASIN 200 wrapper 거부 룰 포함, Risk R8)

---

## M8 Completed (2026-03-10)

### Changes Made

#### Phase A: Code Quality (P0)
- Deleted PA API dead code: `pa_api_service.rb`, test, and fixture
- Added legacy naming comments to PriceSyncService and Product.needs_price_sync scope
- Fixed CategoryAnalyzerJobTest conditional assertion (replaced with `assert_operator`)
- Updated sync test names/comments for legacy column naming
- Created `.env.example` template
- Verified `.gitignore` covers `.env*`

#### Phase B: Product Model Validations (P1)
- Added `sourcing_status`, `scraper_status`, `shopify_status` inclusion validations (all `allow_nil: true`)
- Added `price >= 0` numericality validation
- Added `publishable?` method
- Created `test/models/product_test.rb` (10 tests, ~12 assertions)

#### Phase C: Dashboard Enhancement (P1)
- Added 4 new stat cards (row 2): Total Categories, Shopify Pending, Shopify Failed, Active Pipelines
- Added Recent Sourcing Batches table (category, phase, status, progress%, date)

#### Phase D: Pagination & Category Filter (P1)
- Upgraded `paginate` helper: returns total count + total_pages
- Enhanced pagination partial: "Page X of Y (N total)", First/Last links
- Added `category_id` filter to ProductsController
- Fixed categories/show "All Products" link to pass `category_id`

#### Phase E: Jobs & Status Polish (P1/P2)
- Added Error column to Recent Job Executions (queries SolidQueue::FailedExecution)
- Expanded status_badge colors: publishing, draft, failed, synced, collected
- Deleted dead `filter_controller.js` (no-op Stimulus controller)
- Removed `data-controller="filter"` from recommendations index
- Added breadcrumb back-link to categories/show

### Deleted Files (4)
```
app/services/pa_api_service.rb
test/services/pa_api_service_test.rb
test/fixtures/files/pa_api_sample.json
app/javascript/controllers/filter_controller.js
```

### Created Files (2)
```
.env.example
test/models/product_test.rb
```

### Modified Files (~13)
```
app/models/product.rb
app/controllers/application_controller.rb
app/controllers/dashboard_controller.rb
app/controllers/products_controller.rb
app/controllers/jobs_controller.rb
app/helpers/application_helper.rb
app/services/price_sync_service.rb
app/views/dashboard/index.html.erb
app/views/shared/_pagination.html.erb
app/views/categories/show.html.erb
app/views/jobs/index.html.erb
app/views/recommendations/index.html.erb
test/jobs/category_analyzer_job_test.rb
test/jobs/sync_jobs_test.rb
```

---

## M7 Completed (2026-03-10)

### Changes Made
- Replaced PA API with Scrapling-based unified scraping (4-phase pipeline: url_list → scrapling_collect → filter → final_filter)
- Added Shopify Custom App integration (GraphQL Admin API 2025-01)
- 3 new services: ShopifyApiService, ShopifyPublishService, ShopifyPriceSyncService
- 2 new jobs: ShopifyPublishJob, ShopifyPriceSyncJob (daily 10am)
- DB: categories.margin_rate (decimal, default 50%), products.shopify_error (varchar2 2000)
- Unified scraper: product_page.py parser + main.py v2 (StealthyFetcher + httpx fallback)
- Frontend: batch publish Stimulus controller, Shopify status filter, category margin editor, Jobs page Shopify section
- Fixed BigDecimal ID routing bug (to_param override in ApplicationRecord)

### Commit
- `cff3f3b` feat: implement M7 (Scrapling Integration + Shopify Publish)
- Pushed to origin/master

---

## Next Action

- [ ] Shopify Access Token 발급 (사용자 — Section 3.1 가이드 참조)
- [ ] `pip install "scrapling[fetchers]"` + `scrapling install` (실제 모드 전환 시)
- [ ] Production deployment preparation

---

## Session Notes

### 2026-05-01 (PR6+PR7 — DX + OpenAPI 메타 마무리)
- 4 commit: 7ef7663 (PR6 README + .env M9 vars + requirements pin), 36cc34c (.gitignore exception), f9d50c6 (PR7 OpenAPI 메타 + Rails truncate warn)
- D2-D6: scraper/README.md (931 단어), .env.example +17 M9 vars, requirements.txt Py 3.10+ comment
- P2-1 + R-NEW-10: FastAPI openapi_tags=[5 그룹], 14 endpoint tags+summary+202, BatchScrapeRequest examples, Rails sanitize warn log
- Codex Gate: PR6 APPROVE 즉시 / PR7 REVISE (misread) → APPROVE
- 회귀: 18 pass / 0 fail
- docs/scraper-p2-fixes-2026-05-01.md 작성
- 최종 누적: audit → P0 (5 commit) → P1 (6 commit) → P2 (4 commit) = 15 commits, 45 pass / 0 fail
- 잔존 R-CARRY-13 (24h soak) + R-CARRY (Rails ADB cert) 만 환경 의존, 코드 사이드 P0/P1/P2 모두 closed

### 2026-05-01 (PR4+PR5 — F2/F3/F4 + Rails sanitize)
- 6 commit: 7934ea7 (PR4 F4+F2+F3), 231c554 (PR4 in-flight requeue), ec87ddc (PR4 position-track), ac66916 (PR4 F2 invariant), 6537647 (PR5 sanitize+JSON), 91d62aa (PR5 backcompat+depth)
- F4 batch isolation (asyncio.Lock), F2 per-channel queues, F3 ban → drain + redistribute (in-flight 포함)
- Rails recursive_sanitize: String 모든 깊이 sanitize, Hash/Array 깊이 4 한계, JSON 사전직렬화 backcompat, asin regex
- Codex Gate cascade: PR4 4 round (high→medium→medium→low) → APPROVE, PR5 2 round (high→medium) → APPROVE
- 회귀: scraper 7/7 pass. Rails test 는 Oracle ADB 인증서 (ORA-29024) 로 로컬 미실행, 16 케이스 정적 작성됨
- 잔존: R-CARRY-13 (100-ASIN 24h soak) + ADB wallet 갱신 + DECODO/SMARTPROXY 환경 변수
- docs/scraper-p1-fixes-2026-05-01.md 작성

### 2026-05-01 (JKI-98 P0 4건 즉시 fix)
- 5 commit: 657d0c9 (D1 boot), 81d0d7c (PR2 proxy+auth+Pydantic), 1a21df7 (PR2 follow-up), 8d1c6e0 (PR3 durability), 1965f6e (PR3 follow-up)
- 4개 P0 (D1 boot, C1/F1 proxy, F5 durability, C2/F9 auth) + 5개 HIGH (C3/F6/F7/F8/H4) + 다수 P1 입력검증 (Q2-Q4)
- 신규 산출물: scripts/replay_fallback.py (멱등 replay), /readyz endpoint
- Codex Gate: PR1 APPROVE / PR2 REVISE-then-APPROVE / PR3 REVISE-then-APPROVE (cascade high → medium 작동)
- 회귀 테스트: 20/20 pass (auth 9 + 입력검증 6 + happy path 5)
- docs/scraper-p0-fixes-2026-05-01.md 작성
- 잔존 Risk: F4 (batch isolation, P1), F3 (ban redistribute, P1), 100-ASIN 24h soak 미수행 (별도 24h)
- Service 부팅 가능 상태 복귀: bin/dev 의 scraper line 정상 기동, /health 200, /readyz 인증 200

### 2026-05-01 (Scraper A — 5-skill 통합 리뷰)
- /review /codex /browse /devex-review /qa 5종 → P0 4건, P1 7건, P2 7건, Risk 15건 도출
- **CRITICAL**: D1 service boot 불가 (rate_limiter.py:11 잘못된 import) — Procfile.dev 명령으로 즉시 ImportError, 3f24372 commit 이후 라이브 부팅 미검증
- **CRITICAL**: C1/F1 proxy/profile 가 실제 fetch 에 적용 안 됨 (worker_pool.py:257) — 50K 비용 절감 메커니즘 무력
- **CRITICAL**: F5 checkpoint 가 Rails 영속화 전에 success 마킹 — flush 실패 시 silent data loss
- /codex (high reasoning, 600s, 24K tokens) 가 10건 독립 발견 (C1/F1, F2-F10)
- /qa live mock 모드: 20 테스트 중 10 fail — auth 부재 (Q1), Pydantic Field 부재 (Q2-Q4), nested XSS (Q5)
- /devex-review TTHW 점수 2.3/10 (운영 불가 상태)
- Codex Gate 1 (high reasoning) PASS-with-caveats — 5중확인 0/3중1/2중8 일관성
- Codex Gate 2 (high reasoning) APPROVE
- 산출물: docs/scraper-multi-review-2026-05-01.md
- TODO 7-PR plan ~6일 추정, R3/R13 해결을 위한 100-ASIN 24h soak 별도 24h 필요

### 2026-05-01 (Scrape 방식 3-way 비교)
- 3가지 scrape 방식 (현재 Scrapling / gstack /scrape / Jina Reader) 실측 비교 수행
- gstack /scrape: N=10 ASIN, 1.6-2.5s/req, 차단 0, 단 OCI Asia → amazon.sg geo-redirect 확인 (가격 SGD 노출)
- Jina Reader: N=7 ASIN, 1.5-15.4s, 차단 0, US backend (USD 일관), 단 가격 후보 다중·dead-ASIN 200 wrapper
- Codex Gate 1 (verdict-only, 600s/high → 600s/medium → PROCEED-WITH-CAVEATS), Gate 2 (high → medium → APPROVE)
- 결정: 50K 본 작업은 A 유지, 단 비용절감 ROI 와 zero-block 검증을 staged 로 진행
- 단계: 단계 0 prev tool 유지 → 단계 1 100-ASIN 24h soak → 단계 2 staged load test → 단계 3 breakeven cutover
- B gstack /scrape: production 제외, dev ad-hoc 용도만
- C Jina Reader: 하이브리드 fallback + 컨텐츠 사이트 단발 추출 후보
- 13개 Risk 식별, M9 TODO 5건 추가
- 산출물: docs/scrape-comparison-2026-05-01.md

### 2026-03-10 (M8 구현)
- M8 Polish 전체 구현 완료
- 4 files deleted, 2 created, ~13 modified
- 88 tests, 219 assertions, 0 failures, Brakeman 0 warnings

### 2026-03-10 (M7 구현)
- M7 전체 구현 완료 (Scrapling + Shopify Publish)
- 82 tests, 206 assertions, 0 failures, Brakeman 0 warnings
- Commit: cff3f3b → pushed to origin/master

### 2026-02-23 (M5-M6)
- M5 AI Analysis, M6 Sourcing Pipeline 완료

### 2026-02-22 (M3-M4)
- M3 Dashboard + M4 Collectors 완료

### 2026-02-21 (M1-M2)
- Project initialized, Foundation + Schema 완료
