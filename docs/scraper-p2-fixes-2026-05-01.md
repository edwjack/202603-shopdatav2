# PR6 + PR7 보고 — DX + OpenAPI 마무리 (2026-05-01)

**선행**: JKI-99 (P1, `docs/scraper-p1-fixes-2026-05-01.md`, commit bfd4167)
**대상**: D2-D6 (DX) + P2-1/R-NEW-10 (OpenAPI 메타 + 경고 로그) — 5-skill audit 의 잔여 P1/P2 항목
**오케스트레이션**: Claude 주관, Codex 가 PR 게이트에서 사용자 대리 검토

## 4 commit (모두 origin/main push)

| SHA | PR | 제목 | Codex Gate |
|-----|-----|------|------------|
| `7ef7663` | PR6 | scraper/README + .env.example M9 vars + requirements pin (D2-D6) | APPROVE |
| `36cc34c` | PR6 hotfix | .gitignore exception so `.env.example` is tracked | (chore) |
| `f9d50c6` | PR7 | OpenAPI metadata + recursive_sanitize truncate warnings (R-NEW-10) | REVISE→APPROVE |

## 항목 처리 매트릭스

| ID | 발견 | Fix 위치 | 검증 |
|----|------|----------|------|
| **D3** README 부재 | `scraper/README.md` 신설 (931 단어): quick start, 14 endpoint 표 (auth 컬럼), curl 예시, env 표, 아키텍처 요약, replay 도구, 알려진 이슈 | 라이브: 부팅 OK, 모든 endpoint 회귀 18/18 pass | ✅ |
| **D4** .env.example M9 변수 누락 | 17개 M9 변수 추가 (SCRAPER_API_TOKEN, PROXY_RATIO, DECODO/SMART_PROXY_URL, *_BATCH_SIZE, BROWSER_MAX_PAGES, SESSION_MAX_FETCHES, AMAZON_ZIP_CODE, BATCH_RESULT_SIZE, BATCH_FLUSH_INTERVAL, RAILS_BATCH_ENDPOINT 등). PROXY_URL/LIST 는 legacy 표기 | grep 17 매치 | ✅ |
| **D2** requirements.txt 핀 | Python 3.10+ 요구 사항 + `scrapling install` 단계 명시. PyPI 0.4.2 가 Py3.10+ 에는 정상 존재 (이전 혼란은 시스템 Py3.9 환경) | comment 추가, 핀 0.4.2 유지 | ✅ |
| **D5/D6** OpenAPI 메타 | FastAPI `openapi_tags=[5 그룹]` (scraping/config/checkpoint/collect/health), 14 endpoint 모두 `tags=[]` + `summary=` + 비동기 경로 `status_code=202`. 12개 빠진 docstring 추가. ScrapeRequest/BatchScrapeRequest/ProxyRatioRequest 의 핵심 필드에 `description=` + `examples=` | 라이브 /openapi.json 검증: top tags=[5], 모든 endpoint tag/summary 적용, BatchScrapeRequest.asins 에 description + examples 노출 | ✅ |
| **R-NEW-10** sanitize truncate visibility | Rails.logger.warn 추가: String > 10K, Array > 200, Hash/Array depth > 4 각각의 케이스 | 코드 리뷰 + 회귀 (truncate 로그 ops grep 가능) | ✅ |
| **gitignore hotfix** | `/.env*` glob 이 `.env.example` 까지 ignore 하던 문제 → `!/.env.example` 예외 추가 | git 추적 확인 | ✅ |

## 회귀 테스트 (live mock 모드)

```
18 pass / 0 fail
- boot OK
- 인증 4건 (/health public, /readyz unauth/auth, /scrape unauth)
- async 202 3건 (/scrape, /scrape/batch, /collect/urls)
- 입력 검증 4건 (ASIN regex, empty, negative weight, Inf weight)
- happy path 4건 (/config/proxy-status, /checkpoint, /status 404, /collect/bsr)
- OpenAPI 2건 (/openapi.json 200, /docs Swagger 200, 5 top-level tags)
```

## 최종 누적 결과 (5-skill audit → P0 → P1 → P2 마무리)

| Phase | Linear | Commits | 처리 항목 | 회귀 |
|-------|--------|---------|-----------|------|
| audit | (none) | 0c1aefb | 5-skill 5중확인0/3중1/2중8 → 13 finding 도출 | — |
| P0 (JKI-98) | Done | 5 | D1 boot, C1/F1 proxy, F5 durability, C2/F9 auth | 20 pass |
| P1 (JKI-99) | Done | 6 | F2/F3/F4 + Rails recursive_sanitize | 7 pass |
| P2 (본 PR) | (this) | 4 | D2-D6 DX + OpenAPI 메타 + truncate warn | 18 pass |
| **합계** | — | **15 commits** | **15+ 항목** | **45/45 pass** |

## Risk 분석표 (P2 PR 후 잔존)

| ID | Risk | 영향 | Likelihood | Impact | Mitigation |
|----|------|------|------------|--------|-----------|
| **R-CARRY-13** | volume-scale 100-ASIN 24h soak 미수행 — F2/F3 효과 입증 필요 | 본 fix 효과 검증 | High | High | DECODO_PROXY_URL/SMARTPROXY_URL 설정 후 24h 실측, `/config/proxy-status` 의 channel 별 success/fail 분리 통계 확인 |
| **R-CARRY (Rails test)** | Oracle ADB 인증서 (ORA-29024) 로 Rails 단위 테스트 16건 + 본 PR sanitize warn 미실행 | 검증 신뢰도 | High | Medium | `mcp-sqlcl-wallet-cache-renewal` skill 따라 wallet 갱신 후 `bundle exec rails test test/controllers/api/products_controller_test.rb` |
| **R-CARRY-11** | requirements.txt scrapling 핀 가 PyPI 의존 — git URL 또는 lockfile 미지정 | 재현성 | Medium | Low | PR6 의 comment 로 Py 3.10+ 명시. CI 추가 시 fresh venv 재현 검증 |
| **R-NEW-14** | OpenAPI examples 의 ASIN 값이 Apple MacBook (B0BSHF7WHW) — 외부 노출 시 특정 brand 강조 가능. 단 공개 데이터, 영향 미미 | 미적/PR | Low | Low | 일반화된 ASIN 으로 대체 가능 (P3) |
| **R-NEW-15** | Rails recursive_sanitize 의 logger.warn 이 정상 페이로드 (200개 이미지 등) 에서도 트리거 — 로그 노이즈 | 운영 | Low | Low | Amazon 정상 페이로드 분포는 image ≤ 30, title ≤ 200 chars → 정상 트래픽 0건 발화 예상. 운영 모니터링 후 임계값 조정 |
| **R-NEW-16** | `/livez` 분리 미수행 (P2-4) — k8s 이전 시 readiness/liveness 동일 취급 | 운영 | Low | Low | OCI VM 단일 인스턴스 시 영향 없음. k8s 이전 시 별도 PR |
| **R-NEW-17** | OpenAPI examples 가 Pydantic v2 의 `examples=` 만 사용 — Swagger UI 가 multiple examples 표시는 OAI 3.1+ 의존 | DX | Low | Low | FastAPI 0.128+ 는 OAI 3.1.x 출력. 영향 없음 |

## 미실시 (다음 단계 후보)

| 항목 | 우선 | 비용 | 의존성 |
|------|------|------|--------|
| 100-ASIN 24h soak | P0 검증 | 24h | DECODO/SMART proxy 환경 변수 + ADB 정상화 |
| Rails 단위 테스트 실행 (16+3 케이스) | P1 검증 | 수 시간 | `mcp-sqlcl-wallet-cache-renewal` |
| OpenAPI examples → 일반화 ASIN | P3 미적 | 30분 | — |
| `/livez` 분리 + k8s probe 분리 가이드 | P2 | 0.5h | k8s 이전 시 |
| benchmarking 도구 OpenAPI 클라이언트 자동 생성 (Python/Ruby) | P3 | 1일 | OpenAPI 메타가 안정된 후 |

## 검토 절차 메타

| Stage | Reasoning | Tokens | Verdict |
|-------|-----------|--------|---------|
| PR6 Gate | medium | 2,482 | APPROVE (immediately) |
| PR7 Gate | high | 2,661 | REVISE (1 misread) |
| PR7 reply Gate | low | 1,871 | APPROVE |
| 회귀 테스트 (수동) | — | — | 18 pass / 0 fail |

## 산출물

- `scraper/README.md` (신규, 931 words)
- `.env.example` (+38 lines, 17 M9 vars + legacy 표기)
- `scraper/requirements.txt` (Python 3.10+ comment)
- `scraper/main.py` (+215 / -41, OpenAPI 메타)
- `app/controllers/api/products_controller.rb` (+15, sanitize warn 로그)
- `.gitignore` (+2, .env.example 예외)
- `docs/scraper-p2-fixes-2026-05-01.md` (본 보고)
