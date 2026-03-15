require "test_helper"

class ShopifyPriceSyncServiceTest < ActiveSupport::TestCase
  setup do
    ENV['MOCK_EXTERNAL_APIS'] = 'true'
    @category = Category.create!(name: 'Test Sync', slug: 'test-sync', status: 'completed', active: true, margin_rate: 50.0)
    @product = Product.create!(
      asin: 'B0SYNC1234',
      title: 'Sync Test Product',
      price: 40.0,
      category: @category,
      sourcing_status: 'approved',
      scraper_status: 'completed',
      shopify_status: 'published',
      shopify_product_id: 12345,
      shopify_price: 55.0  # outdated price
    )
  end

  teardown do
    Product.where(category: @category).delete_all
    @category.destroy
  end

  test "syncs price when local price changed" do
    result = ShopifyPriceSyncService.sync
    assert result[:updated] >= 1
    @product.reload
    # 40 * 1.5 = 60.0 (was 55.0)
    assert_equal 60.0, @product.shopify_price.to_f
  end

  test "skips when price unchanged" do
    @product.update!(shopify_price: 60.0)
    result = ShopifyPriceSyncService.sync
    assert_equal 0, result[:updated]
  end

  test "returns processed_count" do
    result = ShopifyPriceSyncService.sync
    assert result.key?(:processed_count)
    assert result.key?(:updated)
    assert result.key?(:failed)
  end
end
