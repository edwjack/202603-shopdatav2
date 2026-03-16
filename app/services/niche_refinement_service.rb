class NicheRefinementService
  class RefinementError < StandardError; end

  REFINEMENT_SYSTEM_PROMPT = <<~PROMPT.freeze
    You are a niche product category specialist helping an Amazon product sourcing business identify profitable sub-niches.

    Given a product category, similar successful categories, and recent recommendation history, suggest 3-5 specific niche sub-categories that represent untapped or underserved market opportunities.

    Respond with valid JSON only, no markdown. Use this exact structure:
    {
      "suggestions": [
        {
          "name": "Specific Niche Name",
          "slug": "specific-niche-name",
          "rationale": "Why this niche is promising (2-3 sentences)",
          "estimated_competition": "low|medium|high",
          "target_price_range": "$XX-$XX"
        }
      ]
    }

    Requirements:
    - Suggest 3-5 niches only (no more, no less)
    - Each slug must be lowercase, hyphen-separated, URL-safe
    - estimated_competition must be exactly: low, medium, or high
    - target_price_range must use dollar format: $XX-$XX
    - rationale must be specific and actionable, not generic
  PROMPT

  def self.suggest(category)
    return mock_suggest(category) if MockDataService.mock_mode?

    similar = VectorSearchService.find_similar(category: category, limit: 10)
    recent_recs = category.recommendations.order(created_at: :desc).limit(5)

    prompt = build_refinement_prompt(category, similar, recent_recs)
    result = ClaudeApiService.analyze(
      system_prompt: REFINEMENT_SYSTEM_PROMPT,
      user_prompt: prompt
    )

    suggestions = result['suggestions']
    raise RefinementError, "No suggestions returned from Claude API" if suggestions.blank?

    Rails.logger.info "[NicheRefinementService] #{suggestions.size} suggestions for #{category.name}"
    suggestions
  rescue ClaudeApiService::ApiError => e
    Rails.logger.error "[NicheRefinementService] API error for #{category.name}: #{e.message}"
    raise RefinementError, "Claude API failed: #{e.message}"
  end

  private

  def self.build_refinement_prompt(category, similar, recent_recs)
    lines = []
    lines << "## Target Category"
    lines << "Name: #{category.name}"
    lines << "Slug: #{category.slug}"
    lines << "Amazon Node ID: #{category.amazon_node_id}" if category.respond_to?(:amazon_node_id) && category.amazon_node_id.present?

    if similar.any?
      lines << ""
      lines << "## Similar Successful Categories (up to 10)"
      similar.each do |rec|
        cat_name = rec.respond_to?(:category) ? rec.category&.name : rec.name
        score = rec.respond_to?(:score) ? rec.score : nil
        lines << "- #{cat_name}#{score ? " (score: #{score})" : ""}"
      end
    end

    if recent_recs.any?
      lines << ""
      lines << "## Recent Recommendations for This Category"
      recent_recs.each do |rec|
        lines << "- Score: #{rec.score} | Insight: #{rec.insight&.truncate(150)}"
      end
    end

    lines << ""
    lines << "## Task"
    lines << "Based on the above, suggest 3-5 niche sub-categories of \"#{category.name}\" that would be profitable to source. Focus on specificity, low competition, and strong margin potential."

    lines.join("\n")
  end

  def self.mock_suggest(category)
    [
      {
        'name' => "#{category.name} for Beginners",
        'slug' => "#{category.slug}-beginners",
        'rationale' => "Entry-level products in this category have lower competition and strong search volume from new buyers. Price-sensitive segment with repeat purchase potential.",
        'estimated_competition' => 'low',
        'target_price_range' => '$15-$35'
      },
      {
        'name' => "Premium #{category.name}",
        'slug' => "premium-#{category.slug}",
        'rationale' => "High-end segment is underserved with few quality options. Higher margins offset lower unit volume. Buyers are less price-sensitive.",
        'estimated_competition' => 'medium',
        'target_price_range' => '$50-$120'
      },
      {
        'name' => "#{category.name} Gift Sets",
        'slug' => "#{category.slug}-gift-sets",
        'rationale' => "Bundled gift sets command premium pricing and perform well in Q4. Differentiation through packaging rather than product innovation.",
        'estimated_competition' => 'low',
        'target_price_range' => '$25-$60'
      }
    ]
  end
end
