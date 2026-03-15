class GoogleTrendsCollectorJob < ApplicationJob
  queue_as :scraping

  def perform
    start_time = Time.current
    attempted = 0
    succeeded = 0
    failed = 0

    Category.tracking.active.each do |category|
      attempted += 1
      unless CircuitBreaker.check('google_trends')
        Rails.logger.warn "[Trends] Circuit open, skipping #{category.slug}"
        failed += 1
        next
      end

      result = GoogleTrendsService.fetch(category)
      if result.blank? || result[:error]
        CircuitBreaker.record_failure('google_trends')
        Rails.logger.warn "[Trends] Failed for #{category.slug}, using stale data"
        failed += 1
        next
      end

      CircuitBreaker.record_success('google_trends')

      snapshot = CategorySnapshot.find_or_initialize_by(
        category: category,
        snapshot_date: Date.current
      )
      snapshot.assign_attributes(
        trends_interest: result[:trends_interest],
        trends_cv:       result[:trends_cv],
        trends_yoy:      result[:trends_yoy]
      )
      snapshot.save!
      succeeded += 1
    end

    avg_ms = attempted > 0 ? ((Time.current - start_time) * 1000 / attempted).round : nil
    ScrapeMetric.create!(
      collector_name: 'google_trends',
      run_date: Date.current,
      attempted: attempted,
      succeeded: succeeded,
      failed: failed,
      success_rate: attempted > 0 ? (succeeded.to_f / attempted * 100).round(2) : nil,
      avg_response_ms: avg_ms
    )
  end
end
