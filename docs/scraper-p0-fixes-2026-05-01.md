# JKI-98 P0 4건 즉시 fix — 결과 보고 (2026-05-01)

**Linear**: [JKI-98](https://linear.app/jkincloud/issue/JKI-98)
**선행 리뷰**: `docs/scraper-multi-review-2026-05-01.md` (5-skill audit, commit 0c1aefb)
**오케스트레이션**: Claude 주관, Codex 가 각 PR 게이트에서 사용자 대리 검토 (verdict-only short prompt + stdin redirect, cascade 600s/high → 600s/medium)

## 5개 commit (모두 origin/main push 완료)

| SHA | 제목 | 라인 | Codex Gate |
|-----|------|------|------------|
| `657d0c9` | fix: scraper boot — rate_limiter import path (D1) | +1/-1 | APPROVE (medium) |
| `81d0d7c` | fix: scraper proxy + auth + input validation (C1/F1, C2/F9, Q2-Q4) | +143/-50 | REVISE (high) → 후속 1a21df7 후 APPROVE |
| `1a21df7` | fix: scraper PR2 follow-up — legacy session proxy + /health minimal | +25/-7 | APPROVE (medium) |
| `8d1c6e0` | fix: scraper durability — scraped/persisted split + retry + WAL (F5/C3/F6/F7/F8/H4) | +388/-68 | REVISE (high) → 후속 1965f6e 후 APPROVE |
| `1965f6e` | fix: scraper PR3 follow-up — try/finally batch status + replay idempotency | +85/-46 | APPROVE (medium) |

총: **+642 / -172**, 7개 파일 (소스 5 + script 1 + .gitignore)

## P0 항목별 처리 매트릭스

| ID | 발견 | Fix 위치 | 검증 |
|----|------|----------|------|
| **D1** boot 불가 | `from scraper.config` → `from config` (rate_limiter.py:11) | live `Application startup complete.` | ✅ |
| **C1/F1** proxy bypass | `SessionManager(proxy, profile)` + AsyncStealthySession kwargs threading (proxy/useragent/locale/timezone_id/viewport) | session_manager.py +30, worker_pool.py +6, lifespan +12 | ✅ |
| **C2/F9** auth 부재 | `verify_token` Header dependency, secrets.compare_digest, applied to 13 endpoints | live: 9개 무인증 시도 모두 401, 토큰 시 200 | ✅ |
| **F5** durability gap | 단계적 status pending → scraped → persisted, on_persisted callback, get_unpersisted_results, fallback meta format | unit: scraped 시 remaining 유지, persisted 시 제외 | ✅ |
| **C3/F6** retry 미작동 | mark_failed가 attempts >= MAX_ATTEMPTS 시 status='failed' 전이 | unit: 3회 실패 후 remaining 에서 제외 | ✅ |
| **F7** batch status stale | set_batch_status + run_batch try/finally | unit: empty-channel 경로에서도 'completed' 마킹 | ✅ |
| **H2/F8** flush lock 차단 | flush() 가 lock 안에서 buffer swap 만, HTTP I/O 는 lock 밖 | 코드 리뷰 + add() 도 동일 패턴 | ✅ |
| **H4** SQLite 직렬화 | PRAGMA journal_mode=WAL, synchronous=NORMAL, idx_asin_progress_status | unit: journal_mode → 'wal' | ✅ |
| **Q2-Q4** Pydantic Field | min/max_length, ge/le, ASIN regex, finite validator | live: 음수/Inf/lowercase/empty/10001건 모두 422 | ✅ |

또한 PR2 Gate-2 추가 발견 fix:
- 레거시 single-session 도 proxy/profile 적용
- /health 를 minimal liveness 로 축소 (browser_session 노출 제거)
- /readyz 신설 (auth-only, 상세 정보)

## 회귀 테스트 결과 (live mock 모드)

```
20 pass / 0 fail
- 인증 9건 (auth required, public /health, /readyz separation)
- 입력 검증 6건 (ASIN regex, empty, negative weight, Inf, batch_id=0, oversized list)
- happy path 5건 (/scrape, /scrape/batch, /checkpoint, /status, /collect/bsr)
```

## 새 산출물

| 파일 | 용도 |
|------|------|
| `scripts/replay_fallback.py` | fallback_*.json 리플레이 + checkpoint persisted 마킹, 멱등 (`_is_already_persisted` 필터). dry-run 옵션 |
| `docs/scraper-p0-fixes-2026-05-01.md` | 본 리포트 |
| `/readyz` 엔드포인트 (main.py) | 인증된 상세 health (browser_session, version) |

## Risk 분석표 (Fix 후 잔존 + 새로 도입된 것)

| ID | Risk | 영향 영역 | Likelihood | Impact | Mitigation |
|----|------|-----------|------------|--------|-----------|
| **R-NEW-1** | F5 fix 의 단계적 status 가 외부 caller (Solid Queue cron, Rails ScraperClientService) 의 mark_completed 호출 패턴과 호환 — backcompat shim 으로 처리했으나 caller 가 mark_persisted 까지 호출하는 가정이 깨질 수 있음 | 통합 호환성 | Low | Medium | Rails ScraperClientService grep 후 mark_completed 호출 지점 검사. 현재 Rails 측에서 직접 호출 코드 없음 (shim 동작) |
| **R-NEW-2** | replay_fallback.py 가 Rails 응답 200 에 대해 일괄 mark_persisted 마킹하지만 Rails 가 응답 본문에서 일부 `errors` 를 반환해도 200 — 일부 ASIN 만 실제 저장 | 데이터 무결성 | Medium | Medium | replay 도구를 Rails 응답의 `created/updated/failed/errors` 본문 파싱하도록 보강 (별도 PR). 우선은 Rails 가 dedupe 로 idempotent |
| **R-NEW-3** | /readyz 만 추가하고 /livez 는 미분리 — k8s 등 외부 health probe 가 readiness 와 liveness 동일하게 다룸 | 운영 | Low | Low | 단일 인스턴스 OCI VM 에선 영향 없음. k8s 이전 시 분리 |
| **R-CARRY-3** | run_batch 가 동일 batch_id 로 두 번 호출되는 경우 (Solid Queue retry) 의 race | 동시성 | Medium | High | F4 (batch isolation) 는 P1, 별도 PR4 에서 처리 예정. 임시: cron 에서 동일 batch_id 동시 실행 방지 |
| **R-CARRY-7** | F3 (ban → redistribute_from 미호출) 미해결 | 50K 일정 | Medium | High | P1 PR4 에서 처리 |
| **R-CARRY-13** | volume-scale zero-block 미증명 | 본 fix 의 효과 검증 | High | High | 100-ASIN 24h DIRECT-only soak test (별도 24h, JKI-86 의존) |
| **R-CARRY-11** | requirements.txt 의 scrapling 핀 (==0.4.2) 가 PyPI 미존재 — 새 환경 재설치 불가 | 재현성 | High | Medium | P1 PR6 (DX). git URL 또는 정확한 버전. 본 PR 범위 외 |
| **R-CARRY-12** | DECODO/SMARTPROXY 미구성 시 PR2 의 proxy threading 효과 검증 불가 — 환경 변수 부재 시 url=None → DIRECT 만 작동, 표면적으로 fix 적용 안 된 것처럼 보임 | 운영 | Medium | Medium | .env 에 더미 proxy URL 로 dev 검증 가능. 실측은 JKI-86 진행 시 |
| **R-CARRY-15** | replay tool 이 fallback 파일 처리 후 디스크 청소만 하고, log/metric 보고 미제공 | 운영 | Low | Low | print 로 출력하지만 systemd cron 시 stderr 캡처 필요 |
| **R-NEW-4** | tasks dict (main.py:47) 는 여전히 lock 없음 (P2 항목) | 통계 정확성 | Low | Low | 50K 운영 시 P2-5 처리 |
| **R-NEW-5** | OpenAPI /docs Swagger 메타 (tags/Field/docstring) 는 P2 — 본 PR 미포함 | DX | Low | Low | P2 PR7 |

## 후속 조치 (P1/P2)

| Sprint | PR | 항목 | 추정 |
|--------|-----|------|------|
| 다음 | PR4 | F4 (batch isolation), F3 (ban → redistribute), H2 (flush 추가 검증) | 1일 |
| 다음 | PR5 | Rails recursive_sanitize, batch_upsert 입력 검증 (H3/F10/Q5) | 0.5일 |
| 그 다음 | PR6 | DX: scraper/README, .env.example M9 변수, requirements.txt scrapling 핀 (D2-D6) | 1일 |
| 후순위 | PR7 | OpenAPI 메타 (tags, Field, docstring 12개), /metrics, /livez 분리 | 0.5일 |
| **검증 단독** | (코드 변경 없음) | 100-ASIN 24h DIRECT-only soak (R-CARRY-13) | 24h soak |

## 검토 절차 메타

| Stage | Reasoning | Tokens | Verdict |
|-------|-----------|--------|---------|
| PR1 Gate | medium | 9,220 | APPROVE |
| PR2 Gate (initial) | high | 9,954 | REVISE (3 gaps) |
| PR2 Gate (after rev) | medium | 4,171 | APPROVE |
| PR3 Gate (initial) | high | 2,750 | REVISE (3 gaps) |
| PR3 Gate (after rev) | medium | 2,033 | APPROVE |
| 회귀 테스트 | (수동) | — | 20 pass / 0 fail |

총 소요: 약 28,000 tokens × Codex review.
