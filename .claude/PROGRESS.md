# Progress Tracking - shopdata

**Project**: 202602-shopdata
**Created**: 2026-02-21
**Last Updated**: 2026-03-10

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
| **M8 Polish** | **COMPLETE** | 2026-03-10 | Dead code cleanup, validations, dashboard enhancement, pagination, UX polish |

**Test Suite**: 88 runs, 219 assertions, 0 failures, 0 errors
**Brakeman**: 0 warnings
**Routes**: 30

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
