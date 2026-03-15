class SocialSignalCollectorJob < ApplicationJob
  queue_as :scraping

  def perform
    start_time = Time.current
    attempted = 0
    succeeded = 0
    failed = 0

    Category.tracking.active.each do |category|
      attempted += 1
      unless CircuitBreaker.check('social_signal')
        Rails.logger.warn "[Social] Circuit open, skipping #{category.slug}"
        failed += 1
        next
      end

      result = SocialSignalService.fetch(category)
      if result.blank? || result[:error]
        CircuitBreaker.record_failure('social_signal')
        Rails.logger.warn "[Social] Failed for #{category.slug}, using stale data"
        failed += 1
        next
      end

      CircuitBreaker.record_success('social_signal')

      snapshot = CategorySnapshot.find_or_initialize_by(
        category: category,
        snapshot_date: Date.current
      )
      snapshot.assign_attributes(
        reddit_mentions:  result[:reddit_mentions],
        reddit_sentiment: result[:reddit_sentiment],
        tiktok_views:     result[:tiktok_views]
      )
      snapshot.save!
      succeeded += 1
    end

    avg_ms = attempted > 0 ? ((Time.current - start_time) * 1000 / attempted).round : nil
    ScrapeMetric.create!(
      collector_name: 'social_signal',
      run_date: Date.current,
      attempted: attempted,
      succeeded: succeeded,
      failed: failed,
      success_rate: attempted > 0 ? (succeeded.to_f / attempted * 100).round(2) : nil,
      avg_response_ms: avg_ms
    )
  end
end
