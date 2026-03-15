class MoversShakersCollectorJob < ApplicationJob
  queue_as :scraping

  def perform
    start_time = Time.current
    attempted = 0
    succeeded = 0
    failed = 0

    # Randomize category order to avoid predictable scraping patterns
    categories = Category.tracking.active.to_a.shuffle
    categories.each_with_index do |category, idx|
      attempted += 1
      unless CircuitBreaker.check('movers_shakers')
        Rails.logger.warn "[Movers] Circuit open, skipping #{category.slug}"
        failed += 1
        next
      end

      result = MoversShakersService.fetch(category)
      if result.blank? || result[:error]
        CircuitBreaker.record_failure('movers_shakers')
        Rails.logger.warn "[Movers] Failed for #{category.slug}, using stale data"
        failed += 1
        next
      end

      CircuitBreaker.record_success('movers_shakers')

      snapshot = CategorySnapshot.find_or_initialize_by(
        category: category,
        snapshot_date: Date.current
      )
      snapshot.movers_data = result[:movers_data].to_json
      snapshot.save!
      succeeded += 1

      # Pause between categories to reduce velocity fingerprinting (3-5 min)
      if idx < categories.size - 1 && !MockDataService.mock_mode?
        pause = rand(180..300)
        Rails.logger.info "[Movers] Category pause: #{pause}s before next category"
        sleep(pause)
      end
    end

    avg_ms = attempted > 0 ? ((Time.current - start_time) * 1000 / attempted).round : nil
    ScrapeMetric.create!(
      collector_name: 'movers_shakers',
      run_date: Date.current,
      attempted: attempted,
      succeeded: succeeded,
      failed: failed,
      success_rate: attempted > 0 ? (succeeded.to_f / attempted * 100).round(2) : nil,
      avg_response_ms: avg_ms
    )
  end
end
