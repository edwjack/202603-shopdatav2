# Scrape 방식 3-way 비교 (2026-05-01)

**대상 프로젝트**: 202603-shopdatav2 (M9 50K Amazon 상품 수집)
**작성 동기**: 사용자가 이전에 사용하던 유료 scraping tool (2,000-5,000 ASIN/day, zero-block, 비용 발생) 을 자체 구축으로 대체해 비용 절감하려는 목표.

## 비교 대상

| Tag | 방식 | 진입점 |
|-----|------|--------|
| **A** | 현재 프로젝트 scraper (Scrapling 기반) | `scraper/main.py` (FastAPI :3211) |
| **B** | gstack `/scrape` skill | `~/.claude/skills/gstack/browse/dist/browse` (bundled Chromium) |
| **C** | Jina Reader | `https://r.jina.ai/<URL>` (server-side fetch) |

## 측정 방법론 (caveat 포함)

| 항목 | A 현재 scraper | B gstack /scrape | C Jina Reader |
|------|---------------|-------------------|----------------|
| 측정 시점 | 2026-04-07 (3주 전) | 2026-05-01 today | 2026-05-01 today |
| 표본 N | 10 ASIN | 10 ASIN | 7 ASIN |
| 채널 | DIRECT (proxy off) | local 브라우저 (OCI Asia IP) | Jina 백엔드 (US IP) |
| 서비스 상태 | 미기동 (벤치 결과 인용) | 직접 실행 | 직접 실행 |

**필수 caveat (Codex Gate 1 지정)**:
1. 표본이 작아 high-volume block-rate 결론은 낼 수 없음
2. A의 수치는 2026-04-07 벤치마크 인용이며 오늘 재검증 안 됨
3. B의 가격 추출 실패는 OCI Asia → amazon.sg geo-redirect 의 영향
4. C는 죽은 ASIN에도 200 wrapper 를 돌려주며, 가격 후보가 다중이라 모호함
5. 본 리포트는 **의사결정 지원**용이지 production-readiness 판정이 아님

## 핵심 비교표 (7개 축)

| 축 | A 현재 scraper | B gstack /scrape | C Jina Reader |
|----|----------------|-------------------|----------------|
| **1. 페이지당 지연** | 7.2s 평균 (4.3-16.9s) | **1.6-2.5s (가장 빠름)** | 1.5-15.4s round-trip |
| **2. 비용** | OCI VM 고정 + 프록시 ($2-3/GB residential, 50K분 $50-200 추정) | **무료** (로컬 머신, 번들 브라우저) | **개인용 무료**, API 키 시 1M tokens/day 무료 그 이상 유료 |
| **3. Anti-bot 내성** | Scrapling stealth + 3채널 프록시 + WorkerPool — 설계상 가장 강함 | 일반 헤드리스 Chromium, 별도 stealth 프로파일 없음 — 고볼륨 시 차단 위험 | Jina 백엔드가 처리 — 호출자는 무관, 단 Jina rate limit 별도 |
| **4. 필드 완성도** (Title/Price/Brand/Rating/Reviews/About/Images/Category) | **8/8 추출 + 13필드 매핑**, 90% 정확도 | 6.5/8 (Title/Brand/Rating/Reviews/About/Images ✅, Price ❌ geo, Category ❌) | 5/8 (Title/Rating/Reviews/About/Brand 일부 ✅, Price 모호, Images 가변, Category ❌) |
| **5. 출력 구조** | **structured JSON 13필드 + Shopify mapper** | ad-hoc JS 평가, 호출마다 사용자가 선택자 작성 | markdown blob, 후처리(LLM/regex) 필수 |
| **6. 운영 복잡도** | FastAPI 서비스 + Scrapling 설치 + 프록시 키 + 체크포인트 SQLite — **무거움** | daemon 1개 자동기동, 환경 변수 0 — **가벼움** | curl 한 줄 — **최저** |
| **7. 50K 스케일 적합성** | **설계 그대로 fit** — checkpoint, 재시도, 일일 quota, BatchResultBuffer, MemoryWatchdog 갖춤 | 단일 daemon, 동시성/체크포인트/재시도/큐 없음 — 50K 스크립트 직접 작성 필요 | rate limit 이 enterprise 변수, 50K curl 가능하나 후처리 비용 증가 |

## 실측 raw 데이터 요약

### B gstack /scrape (10 ASIN)

```
B0BSHF7WHW MacBook         200 OK 2.25s  title✅ price❌ images:14 → SG geo
B09B8V1LZ3 Echo Dot         200 OK 1.98s  title✅ price❌ images:11 → SG geo
0143127748 Body Keeps Score 200 OK 2.52s  title✅ price=S$26 images:1  → SG 명시
B07XJ8C8F5 Echo Dot 4th     200 OK 1.98s  title✅ price❌ images:7
B07ZPC9QD4 AirPods Pro      200 OK 1.66s  title=짧음 price❌ images:7
B0BDHWDR12 Kindle PW        200 OK 1.66s  title✅ price❌ images:5
B07VGRJDFY Nintendo Switch  200 OK 2.13s  title✅ price=S$449 images:4 → SG 명시
B07FZ8S74R Brita pitcher    200 OK 1.79s  title✅ price❌ images:6
B08H93ZRK9 (invalid)        404
B07MLCXBXZ (invalid)        404
요약: 8/10 200 OK (유효 ASIN 100%), 가격 1/8 추출(S$), Title 7/8, 차단 0
```

### C Jina Reader (7 ASIN)

```
B0BSHF7WHW MacBook       200 11.7s 92KB 1223 lines  USD 후보 다중
B09B8V1LZ3 Echo Dot      200 9.4s  131KB 1701 lines USD 후보 다중
0143127748 Body Keeps    200 12.4s 311KB 2166 lines USD $10 후보 다중
B07XJ8C8F5 Echo Dot 4th  200 6.3s   92KB
B07ZPC9QD4 AirPods Pro   200 8.3s   36KB
B07VGRJDFY Nintendo Sw   200 15.4s 269KB
B08H93ZRK9 (invalid)     200 1.5s  624B  "Page Not Found" wrapper
요약: 7/7 200 (1개는 wrapper-on-dead-asin), USD 일관, 차단 0
```

### A 현재 scraper (2026-04-07 벤치)

```
DIRECT 채널 N=10: 100% success 0 blocks
avg 7.2s/req (4.3-16.9s), 141/hr throughput
13필드 dict, Shopify mapper 통과
출처: scraper/data/benchmark/20260407-143046-direct-summary.json
```

## 시나리오별 권장

### 시나리오 1 — **현재 목표 (50K Amazon @ 2-5K/day)**
**권장: A 현재 scraper 유지 + 프록시 활성화**

근거:
- B/C 모두 USD 가격 추출이 불안정하거나 후처리 비용이 큼 — 13필드 구조 출력 부재
- 50K 규모는 checkpoint/재시도/quota 인프라 필수, A만 갖춤
- "이전 유료 tool 2-5K/day zero-block" 을 따라잡으려면 stealth + 프록시 조합이 핵심, B/C 단독으로는 부족
- 다만 A 의 PROGRESS.md known issue (geo-redirect, overview parser, $0 price) 를 우선 해결

### 시나리오 2 — **단발성 페이지 1-2개 정보 빠르게 가져오기**
**권장: C Jina Reader (curl 한 줄)**

근거:
- 컨텐츠 사이트(블로그, 위키, 뉴스)에서는 markdown 출력이 LLM 컨텍스트로 즉시 사용 가능
- 인프라 0, 가입 무관

### 시나리오 3 — **개발 중 임의 사이트 ad-hoc 데이터 추출**
**권장: B gstack /scrape**

근거:
- 로컬에서 즉시 셀렉터 시도, JSON 도출, `/skillify` 로 영구화 가능
- daemon 자동, env 0
- Amazon 같은 anti-bot 강한 사이트에서는 stealth 부족으로 한계 (10건 OK, 1000건은 미검증)

### 시나리오 4 — **하이브리드 (제안)**
**A 의 1차 fetch 가 실패할 때 C 를 fallback** 으로 두는 구조

근거:
- A 가 차단·timeout 시 C 로 raw markdown 만 받아 LLM 으로 13필드 재구성
- 가격은 A 우선 (정확), C 의 가격은 후보 다중이라 사용 시 LLM 후처리 필수
- C 의 Jina 사용량은 50K 중 차단된 잔여분만 → 비용 통제 가능

## Risk 분석표

| # | Risk | 영향 영역 | Likelihood | Impact | Mitigation |
|---|------|-----------|------------|--------|-----------|
| R1 | 표본 N 작아 (B:10, C:7, A:10/3주전) 고볼륨 차단율 모름 | 의사결정 신뢰도 | High | High | A 의 50-ASIN 전체 채널 벤치 (PROGRESS.md M9 TODO) 즉시 실행, 본 리포트는 임시 결정용 |
| R2 | OCI Asia IP → amazon.sg geo-redirect, 가격이 SGD | A,B 모두 | High | High | DECODO_PROXY_URL/SMARTPROXY_URL 즉시 설정, 또는 US VM 전환. Jina 는 영향 없음 |
| R3 | A 의 2026-04-07 수치는 stale, 환경 변화 가능 | 결정 근거 | Medium | Medium | 본 결정 채택 시 1주 내 fresh benchmark 재실행 |
| R4 | gstack /scrape 가 50K 환경에서 차단 폭증할 수 있음 (stealth 미장착) | B 채택 시 | High | High | B는 50K 본선 후보에서 제외, ad-hoc 용도만 |
| R5 | Jina 사용량 폭증 시 rate limit / 유료 전환 비용 | C/하이브리드 | Medium | Medium | API 키 발급 + 일일 quota 모니터링, Anthropic Files API 처럼 cache 활용 |
| R6 | A 의 13필드 중 price/overview parser 가 불안정 (PROGRESS.md known issue) | A 채택 시 | High | Medium | overview 파서 개선, JSON-LD price fallback 강화 (이미 코드에 부분 구현) |
| R7 | "이전 유료 tool 의 2-5K/day zero-block" 이 실은 비공개 stealth 노하우 의존 — A 가 동등 수준 도달 가능성 미검증 | 비용절감 ROI | Medium | High | 100-ASIN 24h soak test 실행 후 차단율 < 1% 확인 시 production 전환, 그 전엔 유료 tool 병행 |
| R8 | Jina 가 죽은 ASIN 에 200 wrapper 반환 → A 또는 호출자가 isValid 판정 누락 시 빈 데이터 적재 | 데이터 품질 | Medium | Medium | "Page Not Found" 문자열 / 본문 < 1KB 패턴 거부 룰 추가 |
| R9 | gstack /scrape 가 호출마다 ad-hoc JS 작성 → 셀렉터 drift, 유지보수 부담 | B 채택 시 | High | Low | `/skillify` 로 영구 skill 화 강제, 또는 운영 후보에서 제외 |
| R10 | 후처리 LLM 비용 (Jina markdown → 13필드) 이 인프라 절감 효과 상쇄 | C 채택 시 | Medium | Medium | Claude Haiku 로 후처리 + prompt cache 활용 시 ASIN 당 < $0.001 가능, 50K=$50 수준 |
| R11 | **프록시 비용이 이전 유료 tool 비용을 초과해 비용절감 동기 무력화** | A 채택 + 프록시 시 | Medium | High | DECODO/SMARTPROXY 실제 견적 받아 50K 분(약 50-200GB 트래픽 추정) 단가 산출 → 이전 유료 tool 월 비용과 비교 후 결정. 무료 DIRECT 채널 비중 (현재 ratio 5:2.5:2.5 의 5) 을 최대화 + 차단 시에만 프록시로 전환하는 adaptive 전략 검토 |
| R12 | **50K 스케일에서 A 의 동시성·checkpoint·BatchResultBuffer 가 미load-test** — 코드 존재만 검증, 부하 검증 안 됨 | A 본선 시 | High | High | 1K-ASIN 단계적 부하 테스트 (1K → 5K → 10K → 50K) 후 통과 시 본선. checkpoint 회복 시뮬레이션 (kill -9 후 재기동) 별도 검증 |
| R13 | volume-scale zero-block 의 *증명* 자체가 미수행 — N=10 은 시그널일 뿐 | 본 리포트 결론 | High | High | 100-ASIN 24h soak + 1K-ASIN 7일 marathon test 가 prod 전 필수 게이트 |

## 비용절감 동기 직접 분석

사용자의 자체 구축 동기는 **비용절감**이며 이전 tool 의 zero-block 안정성을 따라잡는 것이 전제. 이를 권장에 반영:

| 옵션 | 인프라/월 (추정) | 안정성 (현재 증거) | 비용절감 ROI |
|------|-------------------|-------------------|--------------|
| 이전 유료 tool 유지 | 알 수 없음 (사용자 보유 데이터) | **검증된 zero-block 2-5K/day** | 0 (baseline) |
| A + DIRECT only (프록시 없음) | OCI VM 고정 (~$15-50) | N=10 0 blocks, 50K 미검증, geo-redirect 노출 | **최대 절감 가능, 단 차단 시 손실** |
| A + DECODO/SMARTPROXY 50% | $15-50 + $50-200 프록시 | 미측정 (M9 TODO 항목) | 절감 가능 (이전 tool 가격 알아야 확정) |
| A + 100% 프록시 | $15-50 + $100-400 | 가장 안전 (가설) | 이전 tool 보다 비쌀 위험 |
| C Jina 50K + LLM 후처리 | curl 무료 + Haiku $50 추정 | 차단 책임 없음 (Jina 위임) | **절감 명확, 데이터 품질 모호** |
| 하이브리드 A + C | $15-50 + 잔여분만 Jina+LLM | A 가 90% 처리 + C 가 fallback → 안정성↑ | 균형형, 단 복잡도↑ |

**권장 결정 흐름**:
1. 사용자 보유의 *이전 tool 월 비용*을 입력 변수로 잡고
2. A + DIRECT only 로 100-ASIN 24h soak 테스트 (R7, R13) 실행
3. 차단율 < 1% 이면 **A + DIRECT 본선** (최대 절감), 1-5% 면 **A + 적응형 프록시 (R11)**, > 5% 면 **하이브리드 + 이전 tool 일부 잔존**

## 권장 결론

1. **단계 0 — 현재 유료 tool 유지하며**: 비용절감 이전에 *지속 가능한 자체 구축 가능성* 을 우선 증명
2. **단계 1 — A + DIRECT only 100-ASIN 24h soak** (R7·R13): 차단율 측정 후 분기
   - < 1% → 단계 2A (A + DIRECT 본선, 최대 절감)
   - 1-5% → 단계 2B (A + 적응형 프록시, R11 견적 후 결정)
   - > 5% → 단계 2C (하이브리드 A + Jina + LLM 후처리, 이전 tool 부분 잔존)
3. **단계 2 — 1K → 5K → 10K → 50K 단계적 부하 테스트** (R12): checkpoint 회복 별도 시뮬레이션
4. **단계 3 — 이전 tool 월 비용 vs 자체 구축 월 비용** breakeven 산출 후 cutover 결정
5. **B gstack /scrape**: production 후보 제외, dev 시 임의 페이지 점검 용도로만 보존
6. **C Jina Reader**: 차단 fallback (R8 dead-ASIN 200 wrapper 거부 룰 동시 적용) + 컨텐츠 사이트 단발 추출용으로 활용

## 재현 가능한 실행 명령

```bash
# Jina (curl)
curl -sS "https://r.jina.ai/https://www.amazon.com/dp/B09B8V1LZ3"

# gstack /scrape
B=~/.claude/skills/gstack/browse/dist/browse
$B goto "https://www.amazon.com/dp/B09B8V1LZ3"
$B js "(function(){return document.querySelector('#productTitle')?.innerText?.trim();})()"

# 현재 scraper
bin/dev   # FastAPI :3211 기동
curl -X POST localhost:3211/scrape -H 'Content-Type: application/json' \
  -d '{"asins":["B09B8V1LZ3"]}'
```

---

**검토 절차 사용**: Codex Gate 1 (verdict-only, 600s/high → 600s/medium → proceed-with-caveats), Gate 2 예정.
**리포트 raw 데이터**: `/tmp/scrape-cmp/` (jina_*.txt, 본 세션 기준)
