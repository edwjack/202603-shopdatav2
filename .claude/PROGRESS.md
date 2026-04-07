# Progress Tracking - shopdatav2

**Project**: 202603-shopdatav2
**Created**: 2026-02-21
**Last Updated**: 2026-04-07

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
- [ ] Configure DECODO_PROXY_URL and SMARTPROXY_URL for multi-channel testing
- [ ] Overview parser improvement (spec table extraction)
- [ ] 50-ASIN full benchmark with all 3 channels
- [ ] Unit tests for new modules (35 tests planned)

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
