class SocialSignalCollectorJob < ApplicationJob
  queue_as :scraping

  def perform(category_id = nil)
    start_time = Time.current
    attempted = 0
    succeeded = 0
    failed = 0

    categories = if category_id
      [Category.find(category_id)]
    else
      Category.tracking.active.to_a
    end

    categories.each do |category|
      # Concurrent execution guard
      guard_key = "social_collecting_#{category.id}"
      if Rails.cache.read(guard_key)
        Rails.logger.warn "[Social] Already running for #{category.slug}, skipping"
        next
      end
      Rails.cache.write(guard_key, true, expires_in: 30.minutes)

      begin
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
        category.update(last_social_collected_at: Time.current)
        succeeded += 1
      ensure
        Rails.cache.delete(guard_key)
      end
    end

    avg_ms = attempted > 0 ? ((Time.current - start_time) * 1000 / attempted).round : nil
    ScrapeMetric.create!(
      collector_name: 'social_signal',
      run_date: Date.current,
      attempted: attempted,
      succeeded: succeeded,
      failed: failed,
      success_rate: attempted > 0 ? (succeeded.to_f / attempted * 100).round(2) : nil,
      avg_response_ms: avg_ms,
      trigger_type: category_id ? 'on_demand' : 'scheduled'
    )
  end
end
