# Functional Requirements Document (FRD)

## Shopify Dropshipping Business

**Amazon Product Sourcing & Category Killer Strategy**

US Market • $30-$80 Price Range • 50,000 Products Target

| | |
|---|---|
| Version | 1.1 |
| Date | 2026-02-21 |
| Author | JK |
| Status | Draft - Pending Approval |
| Tech Stack | Rails 8 + Oracle ADB 26ai |
| Changes from v1.0 | Feature 0 신규 추가 (Category Recommendation Engine), 기술 스택 Rails 8 + Oracle ADB 26ai로 변경, 추천 점수 계산에 LLM 분석 도입 |

---

## Executive Summary

본 문서는 한국인 운영자가 미국 시장 대상 Shopify 드롭쉬핑 비즈니스를 구축하기 위한 기능 요청서이다. 전체 프로세스는 4단계로 구성된다:

**(0) 카테고리 자동 추천 → (1) 카테고리 선정 및 승인 → (2) Amazon 5만 개 상품 소싱 → (3) Shopify 상품 업로드**

핵심 전략은 Category Killer Shop 운영으로, 특정 니치에 특화된 전문 스토어를 통해 경쟁 우위를 확보한다. 카테고리 추천은 운영자가 매번 시장조사를 할 수 없으므로 **시스템이 자동으로 시장 데이터를 수집·분석하여 데이터 기반 추천을 생성**한다. 점수 산출과 추천 사유 모두 LLM(Claude API)이 원시 데이터를 종합 분석하여 생성하며, Oracle ADB 26ai의 Vector Search를 활용해 과거 유사 패턴 카테고리와의 비교 분석도 수행한다.

---

## 기술 아키텍처 (Technology Architecture)

### 전체 시스템 구성

```
┌──────────────────────────────────────────────────────────────┐
│  Shopify Dropshipping System                                  │
│  Rails 8 + Oracle ADB 26ai                                   │
│                                                               │
│  ┌──────────────────────────────────────────────────────┐    │
│  │  Data Layer: Oracle ADB 26ai                         │    │
│  │  ┌──────────┐ ┌───────────┐ ┌──────────────────┐    │    │
│  │  │ Relational│ │  Vector   │ │  JSON Document   │    │    │
│  │  │ Tables    │ │  Search   │ │  Store           │    │    │
│  │  └──────────┘ └───────────┘ └──────────────────┘    │    │
│  └──────────────────────────────────────────────────────┘    │
│                          │                                    │
│  ┌──────────────────────────────────────────────────────┐    │
│  │  Feature 0: Category Recommendation Engine           │    │
│  │                                                      │    │
│  │  Collectors ──→ Oracle ADB ──→ Claude API ──→ Score  │    │
│  │  (Solid Queue)  (Vector+JSON)  (분석+점수+사유)       │    │
│  │                       ↓                              │    │
│  │              Dashboard (Turbo+Stimulus)               │    │
│  │                  ↓ [승인]                             │    │
│  └──────────────────────────────────────────────────────┘    │
│                          │                                    │
│  ┌──────────────────────────────────────────────────────┐    │
│  │  Feature 1: Sourcing Pipeline                        │    │
│  │                                                      │    │
│  │  URL List → PA API → Filter → Scrape → Final 50K    │    │
│  │  (Rails)   (Rails)  (Rails)  (Python)  (Oracle)     │    │
│  └──────────────────────────────────────────────────────┘    │
│                          │                                    │
│  ┌──────────────────────────────────────────────────────┐    │
│  │  Feature 2: Shopify Upload & Sync                    │    │
│  │                                                      │    │
│  │  Mapping → Bulk Upload → Daily Price/Inventory Sync  │    │
│  │  (Rails)   (Shopify API)  (Solid Queue Schedule)     │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                               │
│  Infra: OCI InstanceAPPCTv3 + Kamal 2 배포                   │
│  외부: Claude API (분석+임베딩), Residential Proxy (스크래핑) │
└──────────────────────────────────────────────────────────────┘
```

### 기술 스택 상세

| 컴포넌트 | 기술 | 비고 |
|---|---|---|
| Framework | Rails 8 | Solid Queue/Cache/Cable native |
| Database | Oracle ADB 26ai | Vector Search, JSON Document Store |
| Background Jobs | Solid Queue | Rails 8 native, 스케줄링 포함 |
| Caching | Solid Cache | Rails 8 native |
| Real-time | Solid Cable | Rails 8 native, 알림/대시보드 |
| Frontend | Turbo + Stimulus | Rails 8 native, SPA 없이 동적 UI |
| AI/LLM | Claude API (Anthropic) | 분석, 점수 산출, 추천 사유, 임베딩 |
| PA API Client | Net::HTTP (Rails native) | Amazon Product Advertising API v5 |
| Scraping Engine | Python microservice | httpx + selectolax + asyncio |
| Proxy | Residential Proxy 서비스 | Phase 2 스크래핑 전용 |
| Shopify 연동 | Shopify Admin API (GraphQL) | Bulk Operations |
| 서버 | OCI InstanceAPPCTv3 | Oracle Linux |
| 배포 | Kamal 2 | Rails 8 native 배포 도구 |
| DB Adapter | activerecord-oracle_enhanced-adapter | Rails ↔ Oracle 연동 |

### Oracle ADB 26ai 활용 영역

| 기능 | 활용 방식 |
|---|---|
| Vector Search | 유사 카테고리 패턴 매칭, 유사 상품 중복 감지, 크로스셀 추천 |
| JSON Document Store | Amazon 상품 JSON 유연한 저장, JSON Duality View로 SQL 쿼리 동시 지원 |
| Relational | 카테고리, 스냅샷, 추천, 상품, 소싱 진행 상태 관리 |
| Graph (선택적) | 카테고리↔상품↔키워드↔트렌드 관계 탐색, 새로운 니치 자동 발견 |

---

## Feature 0: 카테고리 자동 추천 엔진 (Category Recommendation Engine)

### 0.1 목적 (Objective)

운영자가 직접 시장조사를 하지 않아도 **시스템이 자동으로 시장 데이터를 수집·분석하여 유망 카테고리를 추천**한다. 추천 점수와 추천 사유 모두 LLM(Claude API)이 원시 데이터를 종합 분석하여 생성하며, 단순 수학적 가중 합산이 아닌 맥락 기반 다차원 분석을 수행한다.

### 0.2 LLM 중심 분석 vs 기존 수학 기반 비교

| | 기존 (순수 수학) | 본 시스템 (LLM 분석) |
|---|---|---|
| 점수 산출 | 가중 합산 (BSR×0.25 + Trend×0.20 + ...) | Claude가 원시 데이터 전체를 보고 종합 판단 |
| 가중치 | 고정 | 맥락에 따라 유동적 (예: 수면은 건강 트렌드가 더 중요) |
| 패턴 감지 | 불가 | "이 카테고리는 3년 전 텀블러와 유사한 초기 성장 패턴" |
| 분석 범위 | 수치 비교만 | 경쟁 구조, 진입 장벽, 문화적 맥락, 드롭쉬핑 적합도 종합 |
| 추천 사유 | 템플릿 기반 | 데이터에서 도출된 실질적·논리적 인사이트 |

### 0.3 데이터 수집 (Data Collection)

5가지 소스에서 자동 수집하며, 모든 수집은 Solid Queue Job으로 스케줄링된다.

#### Source 1: Amazon BSR (Best Sellers Rank) 추적

| 항목 | 상세 |
|---|---|
| 수집 방법 | PA API SearchItems — 카테고리별 Top 100 |
| 수집 주기 | 매일 |
| 수집 데이터 | BSR 순위, 7일/30일 BSR 변화율, 카테고리 내 평균 가격·리뷰 수, 신규 진입 상품 비율, FBA/FBM 비율 |
| 추천 지표 | BSR 상승률 높으면서 경쟁 상품 수 적은 카테고리 = 기회 |

#### Source 2: Amazon Movers & Shakers

| 항목 | 상세 |
|---|---|
| 수집 방법 | Amazon Movers & Shakers 페이지 크롤링 |
| 수집 주기 | 매일 |
| 수집 데이터 | 24시간 내 BSR 급상승 상품 목록, 카테고리별 집계 |
| 추천 지표 | 3일 연속 같은 카테고리에서 급상승 = 트렌드 신호 |

#### Source 3: Google Trends

| 항목 | 상세 |
|---|---|
| 수집 방법 | Google Trends API (Rails Net::HTTP) |
| 수집 주기 | 주 1회 |
| 수집 데이터 | 12개월 검색량 추세, 계절성 패턴(변동계수), 관련 급상승 검색어, 미국 주별 관심도 |
| 추천 지표 | 검색량 꾸준히 상승 + 계절성 낮음 = Steady 수요 |

#### Source 4: Social Signal (Reddit / TikTok)

| 항목 | 상세 |
|---|---|
| 수집 방법 | Reddit API (무료), TikTok Creative Center 공개 데이터 |
| 수집 주기 | 주 1회 |
| 수집 데이터 | Reddit 인기 서브레딧 상품/카테고리 언급량·감성 분석, TikTok #TikTokMadeMeBuyIt 관련 카테고리 분류 |
| 추천 지표 | 소셜 버즈 상승 = 수요 선행 지표 |
| 대상 서브레딧 | /r/BuyItForLife, /r/shutupandtakemymoney, /r/AmazonTopRated 등 |

#### Source 5: 경쟁 Shopify 스토어 모니터링

| 항목 | 상세 |
|---|---|
| 수집 방법 | 유사 드롭쉬핑 스토어 크롤링 |
| 수집 주기 | 주 1회 |
| 수집 데이터 | 신규 등록 상품 카테고리, 가격대 변화, 컬렉션 구조 변화 |
| 추천 지표 | 경쟁자가 밀고 있는 카테고리 = 검증된 기회 또는 포화 경고 |

### 0.4 수집 스케줄 (Solid Queue)

```yaml
# config/recurring.yml

# 데이터 수집
amazon_bsr_collector:
  class: AmazonBsrCollectorJob
  schedule: every day at 2am

movers_shakers_collector:
  class: MoversShakersCollectorJob
  schedule: every day at 4am

google_trends_collector:
  class: GoogleTrendsCollectorJob
  schedule: every monday at 3am

social_signal_collector:
  class: SocialSignalCollectorJob
  schedule: every wednesday at 3am

competitor_monitor:
  class: CompetitorMonitorJob
  schedule: every friday at 3am

# 분석
category_analyzer:
  class: CategoryAnalyzerJob
  schedule: every day at 6am

# 알림
weekly_recommendation_digest:
  class: WeeklyRecommendationDigestJob
  schedule: every monday at 9am
```

### 0.5 LLM 분석 파이프라인 (Analysis Pipeline)

```
Step 1: 데이터 수집 (Solid Queue Jobs)
  → Amazon BSR, Google Trends, Social, 경쟁사
  → Oracle ADB 26ai에 저장

Step 2: 데이터 정제 + 컨텍스트 구성 (Rails)
  → 카테고리별 원시 데이터를 분석 가능한 형태로 구조화
  → Oracle 26ai Vector Search로 유사 카테고리 히스토리 검색
  → "과거에 비슷한 패턴을 보였던 카테고리는 어떻게 됐나"

Step 3: LLM 종합 분석 (Claude API)
  → 구조화된 데이터 + 유사 사례 + 비즈니스 컨텍스트 전달
  → Claude가 점수 + 점수 근거 + 사유 + 리스크 + 실행 제안 생성

Step 4: 결과 저장 + 알림 (Rails + Oracle)
  → 추천 결과를 Oracle ADB에 저장
  → AI 분석 텍스트를 Vector로 임베딩 → 향후 유사도 검색용
  → 대시보드 Turbo 업데이트 + 이메일 알림
```

### 0.6 LLM 분석 요청 구조

Claude API에 전달되는 분석 프롬프트:

**System Prompt (비즈니스 컨텍스트):**

```
You are a dropshipping market analyst specializing in US Shopify stores.

Business Context:
- 한국인 운영자, 미국 Shopify 드롭쉬핑
- Category Killer Shop 전략
- 가격대 $30-80, CS 최소화 필수
- Steady 수요 우선 (트렌디보다 꾸준한 것)
- 취급불가: 식품, 캠핑, 공구, 성인용품, 사이즈 의류, 전자기기 본체, 유리/세라믹, 가구, 의약품, 라이선스 캐릭터

Analyze the category data and provide:
1. SCORE (0-10): 종합 추천 점수
2. SCORE_BREAKDOWN: 6개 지표별 점수(0-10)와 데이터 근거
3. INSIGHT: 데이터 기반 추천 사유 (한국어)
4. RISKS: 구체적 리스크 요인
5. ACTION_ITEMS: 이 카테고리 진입 시 첫 실행 사항
6. SIMILAR_PATTERN: 과거 유사 성장 패턴 카테고리 비교

Respond in structured JSON.
```

**User Prompt (카테고리별 원시 데이터):**

```json
{
  "category": "Sleep & Rest",
  "amazon_data": {
    "top100_avg_bsr": 45230,
    "bsr_7d_change": -12.5,
    "bsr_30d_change": -18.3,
    "new_entries_30d": 23,
    "avg_price": 42.50,
    "price_range": { "min": 12, "max": 89, "in_range_pct": 85 },
    "avg_reviews": 2847,
    "avg_rating": 4.3,
    "fba_ratio": 0.60,
    "total_products_in_category": 12500
  },
  "google_trends": {
    "interest_12m_avg": 72,
    "interest_trend": "stable_rising",
    "seasonality_cv": 0.08,
    "related_rising": ["weighted eye mask", "sleep spray", "white noise"],
    "yoy_change": "+8%"
  },
  "social": {
    "reddit_monthly_mentions": 340,
    "reddit_sentiment": 0.82,
    "tiktok_hashtag_views": "2.3M",
    "trending_products": ["silk pillowcase", "sunrise alarm"]
  },
  "competitor": {
    "shopify_stores_count": 45,
    "avg_product_count": 120,
    "top_store_monthly_traffic": "85K",
    "price_positioning": "mid-range"
  },
  "similar_historical": [
    {
      "category": "Tumbler & Hydration",
      "when": "2022-Q3",
      "score_at_discovery": 7.5,
      "current_market_size": "$4.2B",
      "outcome": "explosive_growth"
    }
  ]
}
```

### 0.7 LLM 분석 응답 구조

Claude API가 반환하는 분석 결과:

```json
{
  "score": 9.0,
  "score_breakdown": {
    "demand_stability": {
      "score": 9.2,
      "reason": "Google Trends 변동계수 0.08은 추적 중인 전체 카테고리 중 상위 5% 안정성. 12개월 평균 72로 검색 기반이 탄탄하며, YoY +8% 완만한 성장은 버블이 아닌 구조적 수요 증가를 시사"
    },
    "growth_momentum": {
      "score": 8.5,
      "reason": "30일 BSR -18.3%는 판매 가속을 의미. 신규 진입 23개/월은 공급자도 기회를 인지하고 있으나, 아직 포화 단계가 아님"
    },
    "competition_landscape": {
      "score": 8.0,
      "reason": "FBA 비율 60%는 대형 셀러 장악이 아직 심하지 않음을 의미. Shopify 유사 스토어 45개는 경쟁 있지만 Category Killer 포지셔닝으로 차별화 가능"
    },
    "margin_potential": {
      "score": 9.0,
      "reason": "평균 소싱가 기준 $30-80 범위 적합 상품 85%. 수면 용품은 건강 프레임으로 가격 프리미엄 가능"
    },
    "cs_risk": {
      "score": 9.5,
      "reason": "사이즈 없음, 전자 부품 최소, 소모/소형품 위주. 드롭쉬핑 CS 리스크 최하위 그룹"
    },
    "category_killer_fit": {
      "score": 8.8,
      "reason": "'수면 전문 스토어' 컨셉은 미국 소비자에게 직관적. 크로스셀 구조 자연스러움 (아이마스크→디퓨저→화이트노이즈)"
    }
  },
  "insight": "(데이터 기반 추천 사유 — 한국어 상세 텍스트)",
  "risks": [
    "LED 마스크 등 전자기기 포함 시 CS 급증 가능 → 비전자 아이템만 취급 권장",
    "아로마/스프레이류는 항공 배송 제한 가능 → 배송 방식 사전 확인 필요"
  ],
  "action_items": [
    "1단계: 비전자 수면 악세사리 50개로 시작",
    "2단계: 'Sleep Better Shop' 브랜딩으로 Category Killer 포지셔닝",
    "3단계: Sleep Foundation 등 백링크 확보로 SEO 기반 구축"
  ],
  "similar_pattern": "2022 Q3의 텀블러 카테고리와 유사한 초기 안정 성장 패턴"
}
```

### 0.8 6개 분석 지표 (Score Breakdown)

| 지표 | 설명 | 데이터 소스 |
|---|---|---|
| demand_stability | 수요 안정성 — 시즌 변동 없이 꾸준한 수요인가 | Google Trends 계절성 변동계수, 12개월 검색량 추세 |
| growth_momentum | 성장 모멘텀 — 시장이 커지고 있는가 | Amazon BSR 변화율, 신규 진입 상품 수, YoY 성장률 |
| competition_landscape | 경쟁 구도 — 진입 여지가 있는가 | FBA/FBM 비율, 총 상품 수, Shopify 경쟁 스토어 수 |
| margin_potential | 마진 여력 — $30-80 범위에서 마진이 나오는가 | 평균 가격, 범위 내 상품 비율, 소싱가 대비 판매가 |
| cs_risk | CS 리스크 — 고객 문의가 적은 카테고리인가 (낮을수록 좋음) | 사이즈 유무, 전자부품 비율, 평균 리뷰 평점, 반품률 |
| category_killer_fit | Category Killer 적합도 — 전문 스토어로 차별화 가능한가 | 크로스셀 구조, 컨셉 직관성, 콘텐츠 마케팅 연계 가능성 |

### 0.9 Oracle 26ai Vector Search 활용

**유사 카테고리 패턴 매칭:**

현재 수집된 카테고리 데이터를 벡터화하여 과거 성공/실패 카테고리와 유사도 비교. "이 패턴은 2022년 텀블러와 87% 유사"와 같은 인사이트를 Claude 분석 시 참고 자료로 제공.

```sql
SELECT r.category_id, c.name, r.score, r.status,
       VECTOR_DISTANCE(r.insight_vector, :current_vector, COSINE) as similarity
FROM recommendations r
JOIN categories c ON r.category_id = c.id
WHERE r.status IN ('approved', 'sourcing', 'completed')
ORDER BY similarity ASC
FETCH FIRST 5 ROWS ONLY;
```

### 0.10 추천 대시보드 (Turbo + Stimulus)

```
┌─────────────────────────────────────────────────────┐
│  Category Recommendations          [이번 주 신규: 3] │
│─────────────────────────────────────────────────────│
│                                                      │
│  ┌─ Score 9.0 ─────────────────────────────────────┐ │
│  │ 🛏️ Sleep & Rest                    [승인] [거절] │ │
│  │                                                  │ │
│  │ 수요 안정성  ████████░░ 9.2                      │ │
│  │ 성장 모멘텀  ████████░░ 8.5                      │ │
│  │ 경쟁 구도   ████████░░ 8.0                       │ │
│  │ 마진 여력   █████████░ 9.0                       │ │
│  │ CS 리스크   █████████░ 9.5                       │ │
│  │ CK 적합도   ████████░░ 8.8                       │ │
│  │                                                  │ │
│  │ AI 분석:                                         │ │
│  │ Google Trends 12개월 변동계수 0.08로 시즌 영향    │ │
│  │ 없는 steady 수요. 평균 소싱가 $28 대비 Shopify   │ │
│  │ 판매가 $42 설정 시 33% 마진 확보 가능...         │ │
│  │                                    [상세 보기 ▼] │ │
│  └──────────────────────────────────────────────────┘ │
│                                                      │
│  승인됨: Dorm Life (2/15), Sleep (2/18)              │
│  [승인된 카테고리 → 소싱 시작]                        │
└─────────────────────────────────────────────────────┘
```

### 0.11 승인 프로세스

| Step | 내용 |
|---|---|
| Step 1 | 시스템이 자동으로 추천 후보군 생성 (매일 분석, 주간 리포트) |
| Step 2 | 운영자가 대시보드에서 추천 카드 리뷰 (점수, AI 분석 사유, 리스크 확인) |
| Step 3 | 운영자 피드백 — 승인 / 거절(사유 입력) / 보류 |
| Step 4 | 승인된 카테고리 → Feature 1 소싱 파이프라인 자동 트리거 |

---

## Feature 1: 상품 카테고리 선정 (Product Category Selection)

### 1.1 목적 (Objective)

Feature 0에서 시스템이 자동 추천한 카테고리 중 운영자가 최종 승인한 3-5개 카테고리를 확정한다. Feature 0의 추천 엔진이 가동되기 전 초기 세팅 단계에서는 아래 초기 후보군을 기반으로 시작한다.

### 1.2 선정 기준 (Selection Criteria)

#### 1.2.1 필수 조건

- 판매 가격대: $30 ~ $80
- CS(고객 문의) 발생률 최소화 가능한 상품
- Steady 수요 상품 (트렌디보다 꾸준한 수요)
- 미국 문화/생활 중심 타겟팅
- Shopify 구매층 특성 반영
- Category Killer Shop으로 특화 가능한 니치

#### 1.2.2 취급 불가 품목 (Excluded Categories)

| 품목 | 제외 사유 |
|---|---|
| 식품/건강보조식품 | FDA 규제, 유통기한 관리, 반품/교환 CS 과다, 국제 배송 제한 |
| 캠핑/아웃도어 장비 | 대형/중량 제품 배송비 높음, 사용 후 반품 빈번, 안전 관련 CS |
| 공구/하드웨어 | 무게/크기 이슈, 호환성 CS, 안전사고 책임 리스크 |
| 성인용품 | 광고 제한(Facebook/Google Ads), 반품 처리 불가, 결제 게이트웨이 제한 |
| 사이즈 의류/신발 | 사이즈 교환 CS 40%+, 반품률 업계 최고(30-40%), 재고 회전 어려움 |
| 전자기기 본체 | 고장/불량 CS, 보증 이슈, 높은 반품률, A/S 대응 불가 |
| 유리/세라믹 제품 | 배송 중 파손 CS, 교체 배송 비용, 패키징 비용 상승 |
| 가구/대형 제품 | 배송비 마진 잠식, 조립 CS, 파손 교환 비용 과다 |
| 의약품/의료기기 | FDA 승인 필수, 법적 책임, 클레임 리스크 극대 |
| 라이선스 캐릭터 상품 | 저작권/상표권 침해 리스크, Amazon 브랜드 게이팅 |

### 1.3 초기 카테고리 후보군 (Initial Candidates)

Feature 0 추천 엔진이 가동되기 전, 초기 세팅 단계에서의 후보군. 추천 지수는 CS 발생률, 수요 안정성, 마진율, 배송 용이성, Category Killer 차별화도를 종합 평가한 결과이다.

#### #1 — Dorm Life (기숙사 용품 전문) | Score: 9.5/10

| 항목 | 내용 |
|---|---|
| 선정 사유 | 미국 대학생 약 2,000만 명, 매년 8-9월 Back-to-School 시즌 폭발적 수요. 기숙사 필수품(수납, 조명, 침구 악세사리, 데스크 정리)은 사이즈 이슈 없고 CS 극소. Category Killer로 차별화 용이하며 학부모 구매 비율 높아 객단가 유지 가능. |
| 예시 상품 | 데스크 오거나이저, LED 클립 조명, 접이식 수납함, 미니 가습기, 도어 후크 정리대, 침대 사이드 포켓, 케이블 정리함 |
| 타겟 | 18-22세 대학생 + 학부모 (8-9월 시즌 집중, 연중 신입생 유입) |
| 리스크 | 낮음 - 시즌성 있으나 연중 수요 존재, 반품률 5% 미만 |

#### #2 — Sleep & Rest (수면 전문) | Score: 9.0/10

| 항목 | 내용 |
|---|---|
| 선정 사유 | 미국 성인 70%가 수면 문제 경험, $432B 글로벌 수면 산업. 수면 보조 제품은 소모품/악세사리 중심으로 CS 매우 적고, 반복 구매율 높음. Wellness 트렌드와 맞물려 steady 수요. |
| 예시 상품 | 실크 아이마스크, 수면 이어플러그, 아로마 디퓨저, 가중 아이마스크, 수면 스프레이, 화이트노이즈 머신 |
| 타겟 | 25-55세 여성 중심, 수면 품질 개선에 투자 의향 높은 중산층 |
| 리스크 | 매우 낮음 - 비시즌성, 소모품 반복 구매, 사이즈 이슈 없음 |

#### #3 — Anti-Aging Wellness (노화 방지 웰니스) | Score: 8.5/10

| 항목 | 내용 |
|---|---|
| 선정 사유 | 미국 Anti-aging 시장 $62B, 단순 스킨케어를 넘어 holistic wellness로 확장 중. 구아샤, 페이스 롤러, 자세교정 등 기구 중심으로 하면 CS 적고 마진 높음. 40-60대 여성 구매력 최상위. |
| 예시 상품 | 구아샤 세트, 페이스 롤러(옥/로즈쿼츠), 목/어깨 마사지 기구, 자세교정 밴드, 페이셜 스티머 악세사리 |
| 타겟 | 35-65세 여성, 건강과 외모 관리에 적극 투자하는 층 |
| 리스크 | 낮음 - FDA 규제 대상 아닌 기구/악세사리만 취급 시 안전 |

#### #4 — Tumbler & Hydration (텀블러/수분 전문) | Score: 8.5/10

| 항목 | 내용 |
|---|---|
| 선정 사유 | Stanley Cup 현상 이후 텀블러가 패션 아이템화. 텀블러 본체 + 꾸미기 악세사리(스티커, 부츠, 스트로 토퍼, 파우치) 조합으로 객단가 상승 가능. 미국 수돗물 수질 이슈로 필터 텀블러 수요 증가 중. |
| 예시 상품 | 텀블러 부츠/실리콘 바닥, 스트로 토퍼, 텀블러 스티커 팩, 텀블러 파우치/가방, 교체용 뚜껑, 세척 브러시 세트, 필터 스트로 |
| 타겟 | 15-35세 여성 (틱톡/인스타 영향), Gen Z + 밀레니얼 |
| 리스크 | 낮음 - 악세사리 중심으로 사이즈/호환성 이슈 최소 |

#### #5 — Kids Bath & Water Play (아이 목욕/물놀이 전문) | Score: 8.0/10

| 항목 | 내용 |
|---|---|
| 선정 사유 | 미국 가정의 자녀 목욕 시간은 일상 루틴. 목욕 장난감, 버블바스 디스펜서, 물놀이 토이는 소모/교체 주기 짧고 선물 수요도 큼. Eco-friendly 소재 트렌드와 결합하면 프리미엄 포지셔닝 가능. |
| 예시 상품 | 목욕 장난감 세트, 버블 메이커, 배스 크레용, 목욕 수납 네트, 미끄럼 방지 매트(아동용), 물 온도계, 배스밤(아동용) |
| 타겟 | 25-40세 부모 (0-8세 자녀), 선물 구매자 |
| 리스크 | 낮음 - CPSC 인증 확인 필요하나 완구 규정 명확 |

#### #6 — Home Healing & Relaxation (힐링/릴랙스 전문) | Score: 8.0/10

| 항목 | 내용 |
|---|---|
| 선정 사유 | 코로나 이후 at-home self-care 문화 정착. 캔들, 아로마, 명상 도구, 릴랙스 가전 악세사리 등. Candle 시장만 $12.6B. 감성 소비 + 반복 구매(캔들/향) 조합. |
| 예시 상품 | 소이 캔들, 캔들 악세사리(위크 트리머, 스너퍼), 아로마 오일 세트, 명상 쿠션 커버, 아이필로우, 힐링 사운드 머신 |
| 타겟 | 25-55세 여성, 자기관리/셀프케어에 가치 소비하는 층 |
| 리스크 | 매우 낮음 - 소모품 중심, CS 거의 없음 |

#### #7 — Pickleball & Racquet Sports (피클볼 전문) | Score: 7.5/10

| 항목 | 내용 |
|---|---|
| 선정 사유 | 미국 최고 성장 스포츠, 참여 인구 3,650만 명 (48% YoY 성장). 라켓 자체보다 악세사리(그립, 볼, 가방, 보호대) 중심으로 하면 CS 최소. 50대 이상 참여율 높아 구매력 좋음. |
| 예시 상품 | 피클볼 그립 테이프, 교체용 볼 세트, 피클볼 가방, 손목/무릎 보호대, 스코어보드, 그립 오버랩 |
| 타겟 | 35-65세 남녀, 교외 거주 중산층, 커뮤니티 스포츠 참여자 |
| 리스크 | 중간 - 트렌디하나 steady 전환 중, 악세사리 중심이면 안정적 |

#### #8 — Water Filtration & Purity (수질 필터 전문) | Score: 7.5/10

| 항목 | 내용 |
|---|---|
| 선정 사유 | 미국 수돗물 불신 증가 (Flint 사태 이후 지속), Cirkul 성공 사례. 필터 카트리지는 소모품으로 반복 구매 보장. 정수기 악세사리/교체 필터 중심으로 하면 본체 CS 이슈 회피 가능. |
| 예시 상품 | 냉장고 정수 필터(호환), 샤워 필터, 수도꼭지 필터, TDS 측정기, 물병 필터 교체용, 필터 피처 카트리지 |
| 타겟 | 30-55세 건강 의식 가정, 교외 주택 거주자 |
| 리스크 | 중간 - 호환성 정확히 명시 필요, 잘못된 호환 정보 시 CS 발생 |

#### #9 — Travel Essentials (여행 용품 전문) | Score: 7.0/10

| 항목 | 내용 |
|---|---|
| 선정 사유 | 미국인 연간 여행 지출 $1.1T. 패킹 큐브, 여행용 파우치, 보안 지갑 등 소형 악세사리는 CS 적고 impulse buy 비율 높음. 캐리어는 제외하고 악세사리 특화. |
| 예시 상품 | 패킹 큐브 세트, TSA 자물쇠, 여행용 압축 파우치, 목베개, 여권 지갑, 여행용 세면도구 병 세트, 수하물 태그 |
| 타겟 | 25-55세 빈번 여행자, 비즈니스 여행객 + 가족 여행 |
| 리스크 | 낮음 - 소형 아이템으로 배송/반품 이슈 적음. 캐리어 제외 필수 |

#### #10 — Eco Kids (친환경 아동용품) | Score: 7.0/10

| 항목 | 내용 |
|---|---|
| 선정 사유 | 밀레니얼 부모 세대의 환경 의식으로 친환경 아동용품 수요 급증. 대나무 식기, 실리콘 빨대, 친환경 포장 완구 등. 프리미엄 포지셔닝으로 마진 확보 가능. |
| 예시 상품 | 대나무 아동 식기 세트, 실리콘 빨대 세트, 밀랍 랩, 유기농 면 손수건, 재사용 간식 파우치, 친환경 크레용, 나무 완구 |
| 타겟 | 28-42세 밀레니얼 부모, 환경 의식 높은 중상위 소득층 |
| 리스크 | 중간 - Eco 인증 마케팅 클레임 시 FTC Green Guides 준수 필요 |

#### #11 — Lawn & Outdoor Maintenance (잔디/조경 전문) | Score: 6.5/10

| 항목 | 내용 |
|---|---|
| 선정 사유 | 미국 주택 보유자 약 8,300만, 잔디 관리는 문화적 필수. 스프링클러 악세사리, 정원 도구 교체부품, 조경 장식 등. 시즌성 있으나 봄-가을 6개월 꾸준한 수요. |
| 예시 상품 | 스프링클러 헤드 교체, 정원 호스 노즐, 잔디 가장자리 차단막, 태양광 정원등, 화분 받침대, 잡초 방지 매트 |
| 타겟 | 35-65세 교외 주택 소유자, DIY 정원 관리자 |
| 리스크 | 중간 - 시즌성(3-10월), 일부 아이템 사이즈/호환성 확인 필요 |

#### #12 — Color Theme Shop (컬러 테마 전문) | Score: 6.5/10

| 항목 | 내용 |
|---|---|
| 선정 사유 | 유니크한 컨셉으로 SNS 바이럴 가능성 높음. 특정 색상(Sage Green, Lavender)으로 통일된 라이프스타일 상품 큐레이션. TikTok/Instagram aesthetic 소비 트렌드와 부합. |
| 예시 상품 | 세이지 그린: 머그컵, 캔들, 수건, 파우치, 폰케이스, 펜 세트 / 라벤더: 아이마스크, 노트, 향초, 텀블러, 키보드 패드 |
| 타겟 | 18-30세 여성, SNS aesthetic 소비, 인테리어/라이프스타일 관심층 |
| 리스크 | 높음 - 컨셉 차별화는 강하나 재고 관리 복잡, 색상 매칭 CS 가능 |

#### #13 — Specialty Laundry & Cleaning (전용 세탁/세정 전문) | Score: 6.0/10

| 항목 | 내용 |
|---|---|
| 선정 사유 | 일반 세제가 아닌 특수 용도 세정제(운동화 세정, 스테인리스 클리너, 가죽 케어 등)는 니치하지만 충성 고객 확보 가능. 소모품으로 반복 구매. |
| 예시 상품 | 운동화 세정 키트, 스테인리스 클리너, 가죽 컨디셔너, 그라우트 클리너, 세탁기 세정제, 얼룩 제거 스틱, 섬유 탈취 스프레이 |
| 타겟 | 25-45세 남녀, 집 관리에 관심 있는 가정 |
| 리스크 | 중간 - 화학 성분 규제 확인 필요, 배송 중 액체 누출 주의 |

---

## Feature 2: Amazon 상품 소싱 (Product Sourcing Pipeline)

### 2.1 목표 (Objective)

승인된 카테고리를 기반으로 Amazon에서 **최종 5만 개 상품**을 소싱한다. PA API + HTTP 스크래핑 하이브리드 방식으로 효율성과 데이터 완성도를 모두 확보한다.

### 2.2 소싱 파이프라인 플로우 (Pipeline Flow)

```
Phase 0 → Phase 1 → Phase 1.5 → Phase 2 → Phase 3
URL List   PA API    Filter      Scrape    Final 50K
```

#### Phase 0: 상품 URL 리스트 생성

| 항목 | 상세 |
|---|---|
| 저장 형식 | `{category}_{yyyymmdd}_urllist.md` |
| 수집 방법 | Amazon Best Sellers, New Releases, Movers & Shakers 페이지 크롤링 |
| 목표 수량 | 카테고리당 15,000-20,000개 ASIN (필터링 후 5만개 목표) |
| 포함 필드 | ASIN, URL, 카테고리명, 수집일시 |

#### Phase 1: PA API — 대량 기본 데이터 수집

| 항목 | 상세 |
|---|---|
| API | Amazon Product Advertising API v5 — GetItems / SearchItems |
| 처리 속도 | 10개/요청 × 초당 1요청 = 분당 600개 상품 |
| 수집 필드 | asin, url, title, brand, price, aboutThis(Features), category, tags, images(3단계) |
| 차단 리스크 | 없음 (공식 API) |
| 예상 소요 | 7만개 ASIN 기준 ≈ 2시간 |

#### Phase 1.5: 데이터 정제 및 필터링

PA API 데이터에서 취급 불가 및 Risk 상품을 필터링한다.

| 필터 규칙 | 설명 |
|---|---|
| 가격 범위 | $30 미만 또는 $80 초과 상품 제외 |
| 취급 불가 키워드 | title/category에 식품/캠핑/공구/성인/의류 사이즈 관련 키워드 포함 시 제외 |
| 브랜드 게이팅 | Amazon 브랜드 등록 필요 상품(예: Apple, Nike) 제외 |
| 리뷰 필터 | 평점 3.5 미만 또는 리뷰 10개 미만 제외 |
| 위험 상품 키워드 | FDA, prescription, regulated, hazmat, flammable, weapon 등 포함 시 제외 |
| 중복 제거 | ASIN 기준 중복 상품 제거, 유사 상품명 그룹핑 |

#### Phase 2: HTTP 스크래핑 — 보완 데이터 수집

| 항목 | 상세 |
|---|---|
| 방식 | Python microservice — httpx (async HTTP/2) + selectolax (HTML 파싱) + 정규식 (JS 변수 추출) |
| 대상 URL | `https://www.amazon.com/dp/{asin}` — Phase 1의 asin 기반 상세 페이지 접근 |
| 수집 필드 | images(7단계 상세), overview(상품 속성), options(변형), quantity(재고) |
| 처리 속도 | 5병렬 × 2-5초 딜레이 = 분당 ~100개 |
| 차단 방지 | UA 로테이션(20-30개), Residential Proxy, 랜덤 딜레이, 세션/쿠키 관리 |
| 실패 처리 | 실패 ASIN 재시도 큐 → 시간차 두고 재시도 (3회 최대) |
| 예상 소요 | 5만개 기준 ≈ 8-10시간 (프록시 상황에 따라 변동) |

#### Phase 3: 최종 필터링 → 5만개 확정

| 필터 규칙 | 설명 |
|---|---|
| 재고 필터 | quantity < 3 상품 제외 (품절 위험) |
| 이미지 필터 | 메인 이미지 없는 상품 제외 |
| 설명 필터 | aboutThis(Features) 비어있는 상품 제외 |
| 최종 목표 | 필터링 후 최종 50,000개 상품 확정 |

### 2.3 데이터 스키마 (Data Schema)

최종 상품 데이터는 업로드된 JSON 구조와 동일한 형태로 저장된다.

| Field | Type | Source | Description |
|---|---|---|---|
| asin | String | PA API | Amazon Standard Identification Number (PK) |
| url | String | PA API | Amazon 상품 상세 페이지 URL |
| title | String | PA API | 상품명 |
| brand | String | PA API | 브랜드명 |
| price | Number | PA API | 판매 가격 (USD) |
| aboutThis | Array(JSON) | PA API | 상품 특징 (Features) 배열 |
| category | String | PA API | 최하위 카테고리명 |
| tags | Array(JSON) | PA API | 카테고리 계층 배열 |
| images | Array(JSON) | Scraping | 7단계 해상도 이미지 배열 |
| overview | Array(JSON) | Scraping | 상품 속성 테이블 (Scent, Color 등) |
| options | Object(JSON) | Scraping | 변형 옵션 (사이즈/색상 등) |
| quantity | Number | Scraping | 재고 수량 |
| title_vector | VECTOR(1536) | System | 유사 상품 검색용 임베딩 |
| shopify_product_id | Number | System | Shopify 연동 ID |
| shopify_status | String | System | Shopify 상품 상태 |
| shopify_price | Number | System | Shopify 판매 가격 (마진 적용) |
| pa_api_synced_at | DateTime | System | PA API 동기화 시각 |
| scraping_synced_at | DateTime | System | 스크래핑 동기화 시각 |
| shopify_synced_at | DateTime | System | Shopify 동기화 시각 |

### 2.4 업데이트 주기 (Update Strategy)

| 데이터 그룹 | 주기 | 사유 |
|---|---|---|
| 가격 (price) | 매일 | Amazon 가격 변동 빈번 → Shopify 판매가 동기화 필수 |
| 재고 (quantity) | 매일 | 품절 상품 자동 비활성화, 재입고 시 활성화 |
| title, aboutThis | 주 1회 | 상품명/설명 변경 빈도 낮음 |
| images, overview, options | 월 1회 | 거의 변경되지 않는 정적 데이터 |

---

## Feature 3: Shopify 상품 업로드 (Product Upload to Shopify)

### 3.1 목적 (Objective)

소싱 완료된 5만 개 상품을 Shopify 스토어에 자동 업로드한다. Shopify Admin API(GraphQL)를 활용하여 대량 상품 등록, 카테고리 매핑, 이미지 등록을 자동화한다.

### 3.2 매핑 규칙 (Field Mapping)

| Amazon Field | Shopify Field | Mapping 규칙 |
|---|---|---|
| title | title | 그대로 매핑 (필요 시 SEO 최적화 후처리) |
| price | variants[0].price | Amazon 가격 × 마진율(1.3-1.5배) 적용 |
| aboutThis | body_html | Features 배열 → HTML `<ul><li>` 변환 |
| images[].hiRes | images[].src | hiRes URL 우선, 없으면 large URL 사용 |
| category | product_type | Amazon 카테고리 → Shopify product_type |
| tags | tags | Amazon 카테고리 계층 → Shopify tags 변환 |
| brand | vendor | Amazon brand → Shopify vendor |
| options | variants | 변형 옵션 → Shopify variant 구조 변환 |
| quantity | inventory_quantity | 재고 수량 → Shopify inventory level |
| asin | metafields | ASIN을 metafield로 저장 (추적용) |
| overview | metafields | 상품 속성 → metafield로 저장 |

### 3.3 업로드 방식 (Upload Method)

#### 3.3.1 Shopify Admin API (GraphQL)

- Bulk Operations API 활용 — JSONL 파일로 대량 업로드
- Rate Limit: 초당 2회 × cost 1,000 (GraphQL cost-based throttling)
- 5만 개 상품 예상 소요: ~4-6시간 (Bulk Operations 사용 시)

#### 3.3.2 업로드 플로우

1. 소싱 DB에서 상품 데이터 추출 (1,000개 배치)
2. 매핑 규칙 적용 → Shopify 형식으로 변환
3. 가격 마진 적용 ($30-80 × 1.3-1.5)
4. JSONL 파일 생성 → Shopify Bulk Operation 업로드
5. 업로드 결과 확인 → 실패 상품 재시도 큐 이동
6. 컬렉션 및 카테고리 자동 분류

### 3.4 가격 정책 (Pricing Strategy)

| 항목 | 상세 |
|---|---|
| 기본 마진 | Amazon 가격 × 1.4 (기본값, 카테고리별 조정 가능) |
| 가격 범위 | 최소 $30 ~ 최대 $120 (마진 적용 후 범위 초과 시 제외) |
| Compare-at Price | Shopify compare_at_price = 판매가 × 1.2 (할인 표시 효과) |
| 가격 동기화 | Amazon 가격 변동 시 Shopify 자동 반영 (매일 배치) |

### 3.5 재고 동기화 (Inventory Sync)

- Amazon 재고 < 3: Shopify 상품 자동 비활성화 (Draft 상태)
- Amazon 재고 회복 시: Shopify 자동 활성화 (Active 상태)
- 재고 동기화 주기: 매일 1회 (Phase 2 스크래핑으로 갱신)

---

## 데이터베이스 스키마 (Oracle ADB 26ai)

### 핵심 테이블

```sql
-- 카테고리 마스터
CREATE TABLE categories (
    id             NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name           VARCHAR2(200) NOT NULL,
    slug           VARCHAR2(200) NOT NULL UNIQUE,
    amazon_node_id VARCHAR2(50),
    status         VARCHAR2(20) DEFAULT 'tracking',
    created_at     TIMESTAMP DEFAULT SYSTIMESTAMP,
    updated_at     TIMESTAMP DEFAULT SYSTIMESTAMP
);

-- 일별 스냅샷 (시계열)
CREATE TABLE category_snapshots (
    id               NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category_id      NUMBER REFERENCES categories(id),
    snapshot_date    DATE NOT NULL,
    avg_bsr          NUMBER,
    bsr_7d_change    NUMBER(5,2),
    bsr_30d_change   NUMBER(5,2),
    new_entries      NUMBER,
    total_products   NUMBER,
    avg_price        NUMBER(10,2),
    price_in_range_pct NUMBER(5,2),
    avg_reviews      NUMBER,
    avg_rating       NUMBER(3,2),
    fba_ratio        NUMBER(3,2),
    trends_interest  NUMBER,
    trends_cv        NUMBER(5,4),
    trends_yoy       VARCHAR2(20),
    reddit_mentions  NUMBER,
    reddit_sentiment NUMBER(3,2),
    tiktok_views     VARCHAR2(50),
    raw_data         JSON,
    created_at       TIMESTAMP DEFAULT SYSTIMESTAMP,
    UNIQUE (category_id, snapshot_date)
);

-- AI 추천 결과
CREATE TABLE recommendations (
    id               NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category_id      NUMBER REFERENCES categories(id),
    score            NUMBER(3,1) NOT NULL,
    score_breakdown  JSON NOT NULL,
    insight          CLOB,
    risks            JSON,
    action_items     JSON,
    similar_pattern  CLOB,
    analysis_input   JSON,
    insight_vector   VECTOR(1536, FLOAT32),
    status           VARCHAR2(20) DEFAULT 'pending',
    approved_at      TIMESTAMP,
    rejection_reason VARCHAR2(500),
    model_version    VARCHAR2(50),
    created_at       TIMESTAMP DEFAULT SYSTIMESTAMP,
    updated_at       TIMESTAMP DEFAULT SYSTIMESTAMP
);

-- 벡터 인덱스 (유사 추천 검색)
CREATE VECTOR INDEX idx_recommendation_vector
ON recommendations(insight_vector)
ORGANIZATION NEIGHBOR PARTITIONS
WITH DISTANCE COSINE;

-- 소싱 상품
CREATE TABLE products (
    id                  NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    asin                VARCHAR2(20) NOT NULL UNIQUE,
    category_id         NUMBER REFERENCES categories(id),
    title               VARCHAR2(1000),
    brand               VARCHAR2(200),
    price               NUMBER(10,2),
    about_this          JSON,
    tags                JSON,
    images              JSON,
    overview            JSON,
    options             JSON,
    quantity            NUMBER,
    title_vector        VECTOR(1536, FLOAT32),
    shopify_product_id  NUMBER,
    shopify_status      VARCHAR2(20),
    shopify_price       NUMBER(10,2),
    pa_api_synced_at    TIMESTAMP,
    scraping_synced_at  TIMESTAMP,
    shopify_synced_at   TIMESTAMP,
    created_at          TIMESTAMP DEFAULT SYSTIMESTAMP,
    updated_at          TIMESTAMP DEFAULT SYSTIMESTAMP
);

-- 상품 벡터 인덱스 (유사 상품 검색)
CREATE VECTOR INDEX idx_product_title_vector
ON products(title_vector)
ORGANIZATION NEIGHBOR PARTITIONS
WITH DISTANCE COSINE;

-- 취급불가 키워드
CREATE TABLE excluded_keywords (
    id         NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    keyword    VARCHAR2(200) NOT NULL,
    category   VARCHAR2(100),
    reason     VARCHAR2(500),
    created_at TIMESTAMP DEFAULT SYSTIMESTAMP
);
```

### Vector Search 활용 쿼리 예시

```sql
-- 유사 카테고리 패턴 매칭
SELECT r.category_id, c.name, r.score, r.status,
       VECTOR_DISTANCE(r.insight_vector, :current_vector, COSINE) as similarity
FROM recommendations r
JOIN categories c ON r.category_id = c.id
WHERE r.status IN ('approved', 'sourcing', 'completed')
ORDER BY similarity ASC
FETCH FIRST 5 ROWS ONLY;

-- 유사 상품 중복 감지
SELECT p1.asin, p1.title, p2.asin as similar_asin, p2.title as similar_title,
       VECTOR_DISTANCE(p1.title_vector, p2.title_vector, COSINE) as similarity
FROM products p1, products p2
WHERE p1.asin != p2.asin
  AND VECTOR_DISTANCE(p1.title_vector, p2.title_vector, COSINE) < 0.1
ORDER BY similarity ASC;
```

---

## 인수 기준 (Acceptance Criteria)

| # | Feature | Acceptance Criteria |
|---|---|---|
| AC-1 | Feature 0 | 5가지 데이터 소스(Amazon BSR, Movers&Shakers, Google Trends, Social, 경쟁사)에서 자동 수집 동작 |
| AC-2 | Feature 0 | Claude API를 통한 LLM 기반 점수 산출 및 6개 지표별 근거 생성 |
| AC-3 | Feature 0 | Oracle 26ai Vector Search로 과거 유사 패턴 카테고리 매칭 동작 |
| AC-4 | Feature 0 | 추천 대시보드(Turbo+Stimulus)에서 카드 형태로 추천 확인 가능 |
| AC-5 | Feature 0 | 승인/거절 프로세스 동작, 승인 시 Feature 2 자동 트리거 |
| AC-6 | Feature 1 | 초기 카테고리 후보군 13개 이상 제시, 각 추천 사유/예시상품/타겟/리스크 포함 |
| AC-7 | Feature 1 | 운영자 승인 프로세스 완료 후 최종 3-5개 카테고리 확정 |
| AC-8 | Feature 2 | 카테고리별 URL 리스트 파일 생성 (`{category}_{yyyymmdd}_urllist.md`) |
| AC-9 | Feature 2 | PA API로 기본 데이터 70% 수집 완료 |
| AC-10 | Feature 2 | 데이터 정제: 가격/$30-80, 취급불가 키워드, 브랜드 게이팅, 리뷰 필터 적용 |
| AC-11 | Feature 2 | HTTP 스크래핑으로 보완 데이터 30% 수집 (images, overview, options, quantity) |
| AC-12 | Feature 2 | 재고 3개 미만 필터링 후 최종 50,000개 상품 확보 |
| AC-13 | Feature 3 | Shopify Admin API(Bulk Operations)로 50,000개 상품 업로드 완료 |
| AC-14 | Feature 3 | 매핑 규칙 정상 적용 (price 마진, images, tags, vendor 등) |
| AC-15 | Feature 3 | 일일 가격/재고 동기화 배치 정상 동작 |

---

## 부록: 승인 서명 (Approval)

| 역할 | 이름 | 서명 | 날짜 |
|---|---|---|---|
| 운영자 | JK | | |
