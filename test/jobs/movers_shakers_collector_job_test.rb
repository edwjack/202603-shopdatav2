require "test_helper"

class MoversShakersCollectorJobTest < ActiveSupport::TestCase
  test "uses scraping queue" do
    assert_equal 'scraping', MoversShakersCollectorJob.queue_name
  end

  test "updates movers_data for active categories in mock mode" do
    ENV['MOCK_EXTERNAL_APIS'] = 'true'
    category = Category.tracking.active.first
    snapshot = CategorySnapshot.find_or_create_by!(
      category: category,
      snapshot_date: Date.current
    )
    MoversShakersCollectorJob.perform_now
    snapshot.reload
    assert snapshot.movers_data.present?
    parsed = JSON.parse(snapshot.movers_data)
    assert parsed.is_a?(Hash)
  end

  test "creates scrape_metrics record after run" do
    ENV['MOCK_EXTERNAL_APIS'] = 'true'
    count_before = ScrapeMetric.where(collector_name: 'movers_shakers', run_date: Date.current).count
    MoversShakersCollectorJob.perform_now
    count_after = ScrapeMetric.where(collector_name: 'movers_shakers', run_date: Date.current).count
    assert count_after > count_before
  end
end
