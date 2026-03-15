class VectorSearchService
  def self.find_similar(category:, limit: 5)
    if MockDataService.mock_mode?
      return Recommendation.includes(:category)
                           .where.not(category_id: category.id)
                           .order(score: :desc).limit(limit)
    end

    # Fallback: score-ordered query (vectors not yet populated)
    # TODO: Switch to VECTOR_DISTANCE when embeddings are generated
    sql = ActiveRecord::Base.sanitize_sql_array([
      "SELECT r.id FROM recommendations r WHERE r.status = 'approved' AND r.category_id != ? ORDER BY r.score DESC FETCH FIRST ? ROWS ONLY",
      category.id, limit.to_i
    ])
    ids = ActiveRecord::Base.connection.execute(sql).map { |r| r['ID'] || r['id'] }.compact
    return [] if ids.empty?
    Recommendation.includes(:category).where(id: ids).order(score: :desc)
  rescue => e
    Rails.logger.warn "[VectorSearchService] Query failed: #{e.message}"
    []
  end
end
