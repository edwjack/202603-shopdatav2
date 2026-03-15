require "test_helper"

class AmazonBsrCollectorJobTest < ActiveSupport::TestCase
  test "uses scraping queue" do
    assert_equal 'scraping', AmazonBsrCollectorJob.queue_name
  end

  test "creates or updates snapshots for active categories in mock mode" do
    ENV['MOCK_EXTERNAL_APIS'] = 'true'
    AmazonBsrCollectorJob.perform_now
    snapshot = CategorySnapshot.where(snapshot_date: Date.current).last
    assert snapshot.present?, "Should have a snapshot for today"
    assert snapshot.avg_bsr.present?
    assert snapshot.avg_reviews.present?
    assert snapshot.total_products.present?
    assert_equal Date.current, snapshot.snapshot_date
  end

  test "creates scrape_metrics record after run" do
    ENV['MOCK_EXTERNAL_APIS'] = 'true'
    count_before = ScrapeMetric.where(collector_name: 'amazon_bsr', run_date: Date.current).count
    AmazonBsrCollectorJob.perform_now
    count_after = ScrapeMetric.where(collector_name: 'amazon_bsr', run_date: Date.current).count
    assert count_after > count_before
  end
end
