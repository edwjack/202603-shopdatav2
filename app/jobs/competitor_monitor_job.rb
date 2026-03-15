class CompetitorMonitorJob < ApplicationJob
  queue_as :scraping

  def perform
    start_time = Time.current
    attempted = 0
    succeeded = 0
    failed = 0

    unless CircuitBreaker.check('competitor_monitor')
      Rails.logger.warn "[Competitor] Circuit open, skipping run"
      ScrapeMetric.create!(
        collector_name: 'competitor_monitor',
        run_date: Date.current,
        attempted: 0,
        succeeded: 0,
        failed: 1,
        success_rate: 0.0
      )
      return
    end

    # Aggregate all stores' data into a single hash
    aggregated = {}
    CompetitorStore.active.each do |store|
      attempted += 1
      result = CompetitorMonitorService.fetch(store)
      if result.blank? || result[:error]
        CircuitBreaker.record_failure('competitor_monitor')
        Rails.logger.warn "[Competitor] Failed for store #{store.name}"
        failed += 1
        next
      end
      CircuitBreaker.record_success('competitor_monitor')
      aggregated[store.name] = result[:competitor_data]
      succeeded += 1
    end

    unless aggregated.blank?
      # Write aggregated competitor data to each active category's today snapshot
      Category.tracking.active.each do |category|
        snapshot = CategorySnapshot.find_or_initialize_by(
          category: category,
          snapshot_date: Date.current
        )
        snapshot.competitor_data = aggregated.to_json
        snapshot.save!
      end
    end

    avg_ms = attempted > 0 ? ((Time.current - start_time) * 1000 / attempted).round : nil
    ScrapeMetric.create!(
      collector_name: 'competitor_monitor',
      run_date: Date.current,
      attempted: attempted,
      succeeded: succeeded,
      failed: failed,
      success_rate: attempted > 0 ? (succeeded.to_f / attempted * 100).round(2) : nil,
      avg_response_ms: avg_ms
    )
  end
end
