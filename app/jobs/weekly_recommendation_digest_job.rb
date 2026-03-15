class WeeklyRecommendationDigestJob < ApplicationJob
  queue_as :default

  def perform
    year_week = CategoryAnalysisService.current_year_week
    recs = Recommendation.where(week_number: year_week)
                         .includes(:category).order(score: :desc)
    digest = {
      year_week: year_week, year: Date.current.year,
      total: recs.count, pending: recs.pending.count, approved: recs.approved.count,
      top_category: recs.first&.category&.name, top_score: recs.first&.score,
      categories: recs.map { |r| r.category&.name }.compact
    }
    Rails.logger.info "[WeeklyRecommendationDigest] #{digest.to_json}"
  end
end
