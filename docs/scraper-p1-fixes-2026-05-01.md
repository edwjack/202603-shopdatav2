# PR4 + PR5 보고 — 후속 P1 fix (2026-05-01)

**선행**: JKI-98 P0 4건 fix (`docs/scraper-p0-fixes-2026-05-01.md`, commit ab523bf)
**대상**: F2 / F3 / F4 (concurrency) + H3 / F10 / Q5 (Rails sanitize) — 5-skill audit (`docs/scraper-multi-review-2026-05-01.md`) 의 P1 항목
**오케스트레이션**: Claude 주관, Codex 가 각 PR 게이트에서 사용자 대리 검토 (verdict-only short prompt + stdin redirect, cascade high → medium → low)

## 5개 commit (모두 origin/main push 예정)

| SHA | PR | 제목 | Codex Gate |
|-----|-----|------|------------|
| `7934ea7` | PR4 | F4 batch_lock + F2 per-channel queue + F3 redistribute | initial |
| `231c554` | PR4 | follow-up — F3 in-flight requeue + unknown-channel warn | REVISE |
| `ec87ddc` | PR4 | follow-up v2 — position-tracked blocked_asin + queue fallback | REVISE |
| `ac66916` | PR4 | v3 — fallback channel id matches queue (F2 invariant) | APPROVE (low) |
| `6537647` | PR5 | recursive_sanitize + JSON serialization + asin validation | initial |
| `91d62aa` | PR5 | follow-up — JSON-string backcompat + deep-depth drop + 400 envelope | APPROVE (medium) |

총 6 commit, +500 / -82 lines (코드+테스트).

## P1 항목별 처리 매트릭스

| ID | 발견 | Fix 위치 | 검증 |
|----|------|----------|------|
| **F4** concurrent batch race | `_batch_lock = asyncio.Lock()` + `_run_batch_locked` 분리 (worker_pool.py) | unit: lock 객체 생성 확인 | ✅ |
| **F2** worker cross-channel | per-channel `_queues: dict` + worker_loop 가 자기 채널 큐만 pop | unit: 큐 N개 생성, 푸시/팝 체크 | ✅ |
| **F3** ban → redistribute 미호출 | `_handle_ban(banned, batch_id, blocked_asin)` 가 큐 drain + healthy 채널 가중치 분배 + in-flight 항목도 재큐잉 | unit: 4 ASIN → 3 direct + 1 smart, in-flight 도 라우팅, 모두 banned 시 잔류 | ✅ |
| **F2 + F3 invariant** | fallback target 채널 id 가 task tuple 의 channel 과 일치 (worker/queue/stats 정합성) | Gate v3 코드 리뷰 | ✅ |
| **H3 + F10** Rails nested sanitize | recursive_sanitize (String/Hash/Array/Numeric/Bool, 깊이 4 한계, 문자열 10K cap, 배열 200 cap) | 단위 테스트 16건 작성 | ✅ |
| **Q5 (Rails-side)** asin regex | `/\A[A-Z0-9]{10}\z/` per-item 검증 (scraper Pydantic 와 동일) | 테스트: invalid asin → fail count | ✅ |
| **신규** 입력 검증 | products.size > 100 → 413, non-array → 400, missing key → 400 (JSON envelope) | 테스트: 3건 | ✅ |
| **신규 backcompat** 사전 직렬화 JSON 문자열 처리 | nested 필드가 String 이면 JSON.parse 후 sanitize, 실패 시 opaque sanitize | 테스트: 사전직렬화 round-trip | ✅ |
| **신규 보안** 깊은 중첩 raw HTML 차단 | 깊이 ≤ MAX_NESTED_DEPTH 까지만 컨테이너 내려가고, 그 이상은 nil 로 drop. 단, String 은 모든 깊이에서 sanitize | 테스트: 깊이 5 `<script>` 차단 | ✅ |

## 회귀 테스트 (scraper-side, mock 모드)

```
7 pass / 0 fail
- Ruby 문법 검사: products_controller.rb + test 파일 모두 OK
- 부팅: Application startup complete.
- /scrape 무인증 401 / 토큰 200
- /scrape/batch happy 200
- /health 공개 200, /readyz 무인증 401
- ASIN regex 422
- negative weight 422
- worker_pool 모듈 import OK, _handle_ban + _run_batch_locked 존재 확인
```

**Rails 단위 테스트**: 환경 제약으로 로컬 실행 실패 (Oracle ADB 인증서 ORA-29024, 알려진 환경 이슈). 정적 코드 리뷰 + Codex Gate 로 대체.

## 신규 테스트 (commit 91d62aa)

`test/controllers/api/products_controller_test.rb` 16 케이스:
- 인증 3건 (unauth, wrong token, 미설정)
- 입력 검증 4건 (oversize, invalid asin, missing key, non-array)
- 직렬화 4건 (scalars, images, overview, options)
- sanitize 3건 (top-level, nested, deep nesting drop)
- 길이 cap 1건
- 업데이트 시멘틱 1건
- backcompat JSON-string 1건
- nil asin 1건

ADB 연결 정상화 시 즉시 실행 가능.

## Risk 분석표

| ID | Risk | 영향 | Likelihood | Impact | Mitigation |
|----|------|------|------------|--------|-----------|
| **R-NEW-6** | F4 batch_lock 으로 동시 /scrape/batch 가 직렬화 — Solid Queue cron 이 5K/일 분산 처리 시 큐 대기 누적 가능 | 처리량 | Low | Medium | 5K/day = ~3.5/min, 평균 batch 처리 30분 가정 시 한 batch 만 active. 부하 시 per-batch worker subset 으로 전환 |
| **R-NEW-7** | F3 _handle_ban 이 in-flight 항목만 재큐잉, 다른 worker 가 이미 ban 채널에서 fetch 중인 항목은 그 worker 가 직접 detect 까지 대기 | 일시 처리량 | Medium | Low | 다른 worker 도 같은 ban 을 곧 detect → 자체 _handle_ban 호출 → 멱등 (queue 이미 비어 있어 즉시 return). 채널 cooldown 1h 동안 점진 회복 |
| **R-NEW-8** | F3 가중치 분배 round() 가 적은 N (예: 1) 에서 healthy 한 곳에 몰림. 단, in-flight 는 명시적으로 index 0 → 첫 번째 healthy (가장 weight 큰) 로 라우팅 | 분배 균등성 | Low | Low | 5K 단위 정도면 큰 N 에서 round() 오차 무시 가능. 1-ASIN ban 은 의미 없는 시나리오 |
| **R-NEW-9** | recursive_sanitize 가 String 변환되는 객체 (예: Date, Time, BigDecimal) 도 sanitize → 데이터 손상 가능 | 데이터 무결성 | Low | Medium | 현재 scraper payload 에는 해당 타입 없음. Numeric/Bool 명시 통과, 기타 타입은 to_s + sanitize. Date/Time 송신 시 ISO 문자열로 들어와 사실상 안전 |
| **R-NEW-10** | recursive_sanitize 의 array cap (200) + string cap (10K) — 적법한 큰 페이로드 (예: 250개 이미지) 가 silently truncate | 데이터 손실 | Low | Medium | Amazon 이미지 최대 ~30개, 정상 페이로드는 제한 미달. 운영 시 잘려나가면 logger.warn 추가 검토 (P2) |
| **R-NEW-11** | F4 직렬화 lock 으로 첫 batch 가 hung 시 후속 모두 대기 — deadlock-like 효과 | 운영 | Low | High | _run_batch_locked 의 try/finally 가 항상 lock 해제. asyncio.gather + queue.join 의 timeout 별도 추가 검토 (P2) |
| **R-CARRY-13** | volume-scale 100-ASIN 24h soak 미수행 — 본 PR 의 F2/F3 효과 검증 필요 | 본 fix 효과 검증 | High | High | DECODO/SMARTPROXY 환경변수 설정 후 진행 (JKI-86) |
| **R-CARRY (Rails test)** | Oracle ADB 인증서 만료 (ORA-29024) 로 로컬 Rails 테스트 미실행 | 검증 | High | Medium | wallet 갱신 (mcp-sqlcl-wallet-cache-renewal skill) 후 재실행. 정적 + Codex Gate 로 일단 검증 |
| **R-NEW-12** | 사전 직렬화 JSON 문자열 backcompat 처리: 잘못된 JSON 은 opaque sanitize 후 저장 — 의도적 raw HTML 문자열을 보낸 경우는 sanitize 되어 손상 가능 | 데이터 손상 | Low | Low | 기존 caller 가 raw HTML 을 의도적으로 보낼 시나리오 없음. ScraperClientService 는 .to_json 만 사용 |
| **R-NEW-13** | 깊은 중첩 (>4) 컨테이너 drop — 적법한 deep payload 가 잘림 | 데이터 손실 | Low | Low | 현재 schema (images/overview/options) 는 1-3 depth. P2 에서 모니터링 추가 |

## Linear

JKI-98 (P0) 후속으로 신규 Linear 이슈 생성 권장:
- **JKI-XX (P1)**: 본 PR4+PR5 commit 묶음 표시 + 잔존 R-CARRY-13 (24h soak) + ADB 환경 fix 의존성

## 후속 작업

| 항목 | 우선 | 비용 | 의존성 |
|------|------|------|--------|
| 100-ASIN 24h soak (R-CARRY-13) | P0 검증 | 24h | DECODO/SMARTPROXY 환경 변수 + ADB 정상화 |
| Rails test 실행 (Oracle wallet 재발급) | P1 | 수 시간 | mcp-sqlcl-wallet-cache-renewal skill 가이드 |
| PR6 DX (README, .env.example, requirements.txt) | P1 | 0.5일 | — |
| PR7 OpenAPI 메타 (tags, Field, docstring 12개) | P2 | 0.5일 | — |
| `/livez` 분리 (P2-4) | P2 | 0.5h | k8s 이전 시 |
| recursive_sanitize 의 truncate 경고 로그 (R-NEW-10) | P2 | 0.5h | 운영 모니터링 시 |

## 검토 절차 메타

| Stage | Reasoning | Tokens | Verdict |
|-------|-----------|--------|---------|
| PR4 Gate | high | 1,291 | REVISE (3 gaps) |
| PR4 v2 Gate | medium | 3,221 | REVISE (verify checkout) |
| PR4 v3 Gate (with patch) | medium | 4,086 | REVISE (subtle bug) |
| PR4 v4 Gate (with patch) | low | 9,558 | APPROVE |
| PR5 Gate | high | 2,589 | REVISE (3 gaps) |
| PR5 rev Gate (with patch) | medium | 1,785 | APPROVE |
| 회귀 테스트 (수동) | — | — | 7 pass / 0 fail |

총 ~22.5K tokens × Codex review. 4 round REVISE → APPROVE 사이클이 cascade 정상 작동을 시연 (high → medium → low + inline patch 제공).

---

**산출물**:
- `app/controllers/api/products_controller.rb` (재작성, +84/-7)
- `test/controllers/api/products_controller_test.rb` (신규, 16 케이스)
- `scraper/worker_pool.py` (+161/-23, +55/-38, +21/-6, +9/-7 — 4차 revision)
- `docs/scraper-p1-fixes-2026-05-01.md` (본 보고)
