require "test_helper"

class SyncJobsTest < ActiveSupport::TestCase
  setup do
    ENV['MOCK_EXTERNAL_APIS'] = 'true'
    @category = Category.create!(name: 'Test Sync Category', slug: 'test-sync', status: 'tracking', active: true)
  end

  teardown do
    Product.where(category: @category).delete_all
    @category.destroy
  end

  test "DailyPriceSyncJob runs without error" do
    assert_nothing_raised { DailyPriceSyncJob.perform_now }
  end

  test "WeeklyTitleSyncJob runs without error" do
    assert_nothing_raised { WeeklyTitleSyncJob.perform_now }
  end

  test "MonthlyImageSyncJob runs without error" do
    assert_nothing_raised { MonthlyImageSyncJob.perform_now }
  end

  test "PriceSyncService updates prices for matching products" do
    # Create a product with an ASIN from the price_sync fixture
    fixture = MockDataService.load('price_sync_sample')
    item = fixture.first
    Product.create!(asin: item['asin'], category: @category, title: 'Old Title',
                    price: 10.00, sourcing_status: 'approved')

    result = PriceSyncService.sync(mode: :price)
    assert result[:processed_count] >= 1
    product = Product.find_by(asin: item['asin'])
    assert_not_nil product.data_synced_at
  end

  test "SourcingBatch PHASES does not include legacy pa_api or scrape phases" do
    assert_not_includes SourcingBatch::PHASES, 'pa_api'
    assert_not_includes SourcingBatch::PHASES, 'scrape'
    assert_includes SourcingBatch::PHASES, 'scrapling_collect'
  end

  test "PriceSyncService includes never-synced products in needs_price_sync scope" do
    product = Product.create!(asin: 'TSYNC00001', category: @category, title: 'Never Synced',
                              price: 50.00, sourcing_status: 'approved', data_synced_at: nil)
    assert Product.needs_price_sync.where(id: product.id).exists?
  end
end
