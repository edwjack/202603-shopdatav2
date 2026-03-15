class AmazonBsrCollectorJob < ApplicationJob
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
      unless CircuitBreaker.check('amazon_bsr')
        Rails.logger.warn "[BSR] Circuit open, skipping #{category.slug}"
        failed += 1
        next
      end

      result = AmazonBsrService.fetch(category)
      if result.blank? || result[:error]
        CircuitBreaker.record_failure('amazon_bsr')
        Rails.logger.warn "[BSR] Failed for #{category.slug}, using stale data"
        failed += 1
        next
      end

      CircuitBreaker.record_success('amazon_bsr')

      snapshot = CategorySnapshot.find_or_initialize_by(
        category: category,
        snapshot_date: Date.current
      )
      snapshot.assign_attributes(
        avg_bsr:            result[:avg_bsr],
        bsr_7d_change:      result[:bsr_7d_change],
        bsr_30d_change:     result[:bsr_30d_change],
        new_entries:        result[:new_entries],
        total_products:     result[:total_products],
        avg_price:          result[:avg_price],
        price_in_range_pct: result[:price_in_range_pct],
        avg_reviews:        result[:avg_reviews],
        avg_rating:         result[:avg_rating],
        fba_ratio:          result[:fba_ratio],
        raw_data:           result[:raw_data].to_json
      )
      snapshot.save!
      succeeded += 1

      # Pause between categories to reduce velocity fingerprinting (3-5 min)
      if idx < categories.size - 1 && !MockDataService.mock_mode?
        pause = rand(180..300)
        Rails.logger.info "[BSR] Category pause: #{pause}s before next category"
        sleep(pause)
      end
    end

    avg_ms = attempted > 0 ? ((Time.current - start_time) * 1000 / attempted).round : nil
    ScrapeMetric.create!(
      collector_name: 'amazon_bsr',
      run_date: Date.current,
      attempted: attempted,
      succeeded: succeeded,
      failed: failed,
      success_rate: attempted > 0 ? (succeeded.to_f / attempted * 100).round(2) : nil,
      avg_response_ms: avg_ms
    )
  end
end
