class CategoryAnalysisService
  class AnalysisError < StandardError; end

  # YYYYWW format: 202608 = year 2026, ISO week 8
  def self.current_year_week
    Date.current.strftime('%G%V').to_i
  end

  def self.analyze(category)
    # Step 1: Get latest snapshot (within 7 days)
    snapshot = category.category_snapshots
                       .where("snapshot_date >= ?", Date.current - 7)
                       .order(snapshot_date: :desc).first
    if snapshot.nil?
      Rails.logger.info "[CategoryAnalysisService] Skipping #{category.name} — no recent snapshot"
      return nil
    end

    # Step 2: Find similar historical recommendations
    similar = VectorSearchService.find_similar(category: category, limit: 5)

    # Step 3: Build prompts + call Claude API
    user_prompt = AnalysisPromptBuilder.build_user_prompt(
      category: category, snapshot: snapshot, similar_recommendations: similar
    )
    result = ClaudeApiService.analyze(
      system_prompt: AnalysisPromptBuilder.system_prompt, user_prompt: user_prompt
    )

    # Step 4: Validate response
    validate_response!(result)

    # Step 5: Store recommendation (one per category per ISO year-week)
    year_week = current_year_week
    rec = Recommendation.find_or_initialize_by(category_id: category.id, week_number: year_week)
    rec.assign_attributes(
      score: result['score'].to_f,
      score_breakdown: result['score_breakdown'].to_json,
      insight: result['insight'],
      risks: result['risks'].to_json,
      action_items: result['action_items'].to_json,
      similar_pattern: result['similar_pattern'],
      analysis_input: user_prompt,
      status: rec.new_record? ? 'pending' : rec.status,
      model_version: ClaudeApiService::DEFAULT_MODEL
    )
    rec.save!
    Rails.logger.info "[CategoryAnalysisService] Saved: #{category.name} (score: #{rec.score})"
    rec
  rescue ActiveRecord::RecordNotUnique
    # Race condition: another worker created the record between find and save
    rec = Recommendation.find_by!(category_id: category.id, week_number: current_year_week)
    Rails.logger.info "[CategoryAnalysisService] Duplicate detected, existing record: #{rec.id}"
    rec
  rescue ClaudeApiService::ApiError => e
    Rails.logger.error "[CategoryAnalysisService] API error for #{category.name}: #{e.message}"
    raise AnalysisError, "Claude API failed for #{category.name}: #{e.message}"
  end

  private

  def self.validate_response!(result)
    required_keys = %w[score score_breakdown insight risks action_items similar_pattern]
    missing = required_keys - result.keys
    raise AnalysisError, "Missing keys: #{missing.join(', ')}" if missing.any?

    score = result['score'].to_f
    raise AnalysisError, "Score #{score} out of range" unless score.between?(0, 10)

    metrics = %w[demand_stability growth_momentum competition_landscape margin_potential cs_risk category_killer_fit]
    breakdown = result['score_breakdown']
    missing_m = metrics - breakdown.keys
    raise AnalysisError, "Missing metrics: #{missing_m.join(', ')}" if missing_m.any?

    metrics.each do |key|
      v = breakdown[key]
      raise AnalysisError, "#{key} missing score/reason" unless v.is_a?(Hash) && v.key?('score') && v.key?('reason')
    end
  end
end
