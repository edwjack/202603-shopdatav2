require "test_helper"

class ProductsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @category = Category.create!(name: 'Test Ctrl', slug: "test-ctrl-#{SecureRandom.hex(4)}", status: 'completed', active: true, margin_rate: 50.0)
    @product = Product.create!(
      asin: "B0CTRL#{SecureRandom.hex(3).upcase}",
      title: 'Controller Test Product',
      price: 40.0,
      category: @category,
      sourcing_status: 'approved',
      scraper_status: 'completed',
      shopify_status: 'pending'
    )
  end

  teardown do
    Product.where(category: @category).delete_all
    @category.reload.destroy rescue nil
  end

  test "index renders successfully" do
    get products_path
    assert_response :success
  end

  test "index filters by shopify_status" do
    get products_path(shopify_status: 'pending')
    assert_response :success
  end

  test "show renders successfully" do
    get product_path(@product)
    assert_response :success
  end

  test "publish_shopify redirects with notice" do
    patch publish_shopify_product_path(@product)
    assert_redirected_to product_path(@product)
    assert_match /Publishing to Shopify queued/, flash[:notice]
  end

  test "publish_shopify rejects unapproved product" do
    @product.update!(sourcing_status: 'rejected')
    patch publish_shopify_product_path(@product)
    assert_redirected_to product_path(@product)
    assert_match /must be approved/, flash[:alert]
  end

  test "batch_publish_shopify redirects with count" do
    post batch_publish_shopify_products_path, params: { product_ids: [@product.id] }
    assert_redirected_to products_path
    assert_match /queued for Shopify/, flash[:notice]
  end

  test "batch_publish_shopify handles no selection" do
    post batch_publish_shopify_products_path, params: { product_ids: nil }
    assert_redirected_to products_path
    assert_match /No products selected/, flash[:alert]
  end
end
