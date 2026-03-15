require "test_helper"

class GoogleTrendsCollectorJobTest < ActiveSupport::TestCase
  test "uses scraping queue" do
    assert_equal 'scraping', GoogleTrendsCollectorJob.queue_name
  end

  test "updates trends fields for active categories in mock mode" do
    ENV['MOCK_EXTERNAL_APIS'] = 'true'
    GoogleTrendsCollectorJob.perform_now
    snapshot = CategorySnapshot.where(snapshot_date: Date.current).last
    assert snapshot.present?, "Should have a snapshot for today"
    assert snapshot.trends_interest.present?
    assert snapshot.trends_yoy.present?
    assert_match(/[+-]?\d+%/, snapshot.trends_yoy)
  end

  test "creates scrape_metrics record after run" do
    ENV['MOCK_EXTERNAL_APIS'] = 'true'
    count_before = ScrapeMetric.where(collector_name: 'google_trends', run_date: Date.current).count
    GoogleTrendsCollectorJob.perform_now
    count_after = ScrapeMetric.where(collector_name: 'google_trends', run_date: Date.current).count
    assert count_after > count_before
  end
end
