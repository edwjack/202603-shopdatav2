class AnalysisPromptBuilder
  SYSTEM_PROMPT = <<~PROMPT
    You are a dropshipping market analyst specializing in US Shopify stores.

    Business Context:
    - 한국인 운영자, 미국 Shopify 드롭쉬핑
    - Category Killer Shop 전략
    - 가격대 $30-80, CS 최소화 필수
    - Steady 수요 우선 (트렌디보다 꾸준한 것)
    - 취급불가: 식품, 캠핑, 공구, 성인용품, 사이즈 의류, 전자기기 본체, 유리/세라믹, 가구, 의약품, 라이선스 캐릭터

    Analyze the category data and provide a JSON response with:
    1. "score" (Number 0-10): 종합 추천 점수
    2. "score_breakdown" (Object): 6개 지표별 { "score": Number, "reason": String (한국어) }
       Keys: demand_stability, growth_momentum, competition_landscape, margin_potential, cs_risk, category_killer_fit
    3. "insight" (String): 데이터 기반 추천 사유 (한국어, 200자 이상)
    4. "risks" (Array of String): 구체적 리스크 요인 (최소 2개)
    5. "action_items" (Array of String): 진입 시 첫 실행 사항 (최소 3개)
    6. "similar_pattern" (String): 과거 유사 성장 패턴 카테고리 비교

    Respond ONLY with valid JSON. No markdown, no explanation outside the JSON.
  PROMPT

  def self.system_prompt = SYSTEM_PROMPT

  def self.build_user_prompt(category:, snapshot:, similar_recommendations: [])
    {
      category: category.name, category_slug: category.slug,
      category_description: category.description, target_audience: category.target_audience,
      amazon_data: {
        top100_avg_bsr: snapshot.avg_bsr, bsr_7d_change: snapshot.bsr_7d_change,
        bsr_30d_change: snapshot.bsr_30d_change, new_entries_30d: snapshot.new_entries,
        avg_price: snapshot.avg_price, price_range: { in_range_pct: snapshot.price_in_range_pct },
        avg_reviews: snapshot.avg_reviews, avg_rating: snapshot.avg_rating,
        fba_ratio: snapshot.fba_ratio, total_products_in_category: snapshot.total_products,
        movers_data: snapshot.movers_data_parsed
      },
      google_trends: {
        interest_12m_avg: snapshot.trends_interest, seasonality_cv: snapshot.trends_cv,
        yoy_change: snapshot.trends_yoy
      },
      social: {
        reddit_monthly_mentions: snapshot.reddit_mentions, reddit_sentiment: snapshot.reddit_sentiment,
        tiktok_hashtag_views: snapshot.tiktok_views
      },
      competitor: snapshot.competitor_data_parsed,
      similar_historical: similar_recommendations.map { |r|
        { category: r.category&.name, score_at_discovery: r.score, status: r.status,
          created_at: r.created_at&.strftime("%Y-%m-%d") }
      }
    }.to_json
  end
end
