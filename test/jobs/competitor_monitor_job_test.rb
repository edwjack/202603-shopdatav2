require "test_helper"

class CompetitorMonitorJobTest < ActiveSupport::TestCase
  test "uses scraping queue" do
    assert_equal 'scraping', CompetitorMonitorJob.queue_name
  end

  test "writes aggregated competitor data to today snapshots in mock mode" do
    ENV['MOCK_EXTERNAL_APIS'] = 'true'
    CompetitorMonitorJob.perform_now
    snapshot = CategorySnapshot.where(snapshot_date: Date.current).last
    assert snapshot.present?, "Should have a snapshot for today"
    assert snapshot.competitor_data.present?
    parsed = JSON.parse(snapshot.competitor_data)
    assert parsed.is_a?(Hash)
    assert parsed.keys.any?, "Should have at least one store entry"
  end

  test "creates scrape_metrics record after run" do
    ENV['MOCK_EXTERNAL_APIS'] = 'true'
    count_before = ScrapeMetric.where(collector_name: 'competitor_monitor', run_date: Date.current).count
    CompetitorMonitorJob.perform_now
    count_after = ScrapeMetric.where(collector_name: 'competitor_monitor', run_date: Date.current).count
    assert count_after > count_before
  end
end
