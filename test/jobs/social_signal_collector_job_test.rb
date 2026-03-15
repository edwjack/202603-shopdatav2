require "test_helper"

class SocialSignalCollectorJobTest < ActiveSupport::TestCase
  test "uses scraping queue" do
    assert_equal 'scraping', SocialSignalCollectorJob.queue_name
  end

  test "updates social signal fields for active categories in mock mode" do
    ENV['MOCK_EXTERNAL_APIS'] = 'true'
    SocialSignalCollectorJob.perform_now
    snapshot = CategorySnapshot.where(snapshot_date: Date.current).last
    assert snapshot.present?, "Should have a snapshot for today"
    assert snapshot.reddit_mentions.present?
    assert snapshot.tiktok_views.present?
    assert_match(/\d+(\.\d+)?[KMB]?/, snapshot.tiktok_views)
  end

  test "creates scrape_metrics record after run" do
    ENV['MOCK_EXTERNAL_APIS'] = 'true'
    count_before = ScrapeMetric.where(collector_name: 'social_signal', run_date: Date.current).count
    SocialSignalCollectorJob.perform_now
    count_after = ScrapeMetric.where(collector_name: 'social_signal', run_date: Date.current).count
    assert count_after > count_before
  end
end
