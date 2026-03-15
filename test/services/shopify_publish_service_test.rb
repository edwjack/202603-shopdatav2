require "test_helper"

class ShopifyPublishServiceTest < ActiveSupport::TestCase
  setup do
    ENV['MOCK_EXTERNAL_APIS'] = 'true'
    @category = Category.create!(name: 'Test Shopify', slug: 'test-shopify', status: 'completed', active: true, margin_rate: 50.0)
    @product = Product.create!(
      asin: 'B0TEST1234',
      title: 'Test Product for Shopify',
      brand: 'TestBrand',
      price: 40.0,
      category: @category,
      sourcing_status: 'approved',
      scraper_status: 'completed',
      shopify_status: 'pending'
    )
  end

  teardown do
    Product.where(category: @category).delete_all
    @category.destroy
  end

  test "mock publish sets product to published" do
    result = ShopifyPublishService.publish_single(@product)
    assert result[:success]
    @product.reload
    assert_equal 'published', @product.shopify_status
    assert_not_nil @product.shopify_product_id
    assert_not_nil @product.shopify_synced_at
    assert_nil @product.shopify_error
  end

  test "mock publish calculates shopify_price with margin" do
    result = ShopifyPublishService.publish_single(@product)
    @product.reload
    # price=40, margin=50% → 40 * 1.5 = 60.0
    assert_equal 60.0, @product.shopify_price.to_f
  end

  test "publish rejects zero price" do
    @product.update!(price: 0)
    result = ShopifyPublishService.publish_single(@product)
    assert result[:error]
    assert_equal "Price is zero or nil", result[:error]
  end

  test "publish rejects nil price" do
    @product.update!(price: nil)
    result = ShopifyPublishService.publish_single(@product)
    assert result[:error]
  end

  test "batch publish processes multiple products" do
    product2 = Product.create!(
      asin: 'B0TEST5678',
      title: 'Test Product 2',
      price: 50.0,
      category: @category,
      sourcing_status: 'approved',
      scraper_status: 'completed',
      shopify_status: 'pending'
    )

    results = ShopifyPublishService.publish_batch([@product, product2])
    assert_equal 2, results[:published]
    assert_equal 0, results[:failed]

    product2.destroy
  end

  test "uses default margin when category is nil" do
    @product.update!(category: nil)
    result = ShopifyPublishService.publish_single(@product)
    assert result[:success]
    @product.reload
    # default margin 50% → 40 * 1.5 = 60.0
    assert_equal 60.0, @product.shopify_price.to_f
  end
end
