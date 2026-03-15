require "test_helper"

class ProductTest < ActiveSupport::TestCase
  setup do
    @category = Category.create!(name: 'Test Product Cat', slug: 'test-product-cat', status: 'tracking', active: true)
  end

  teardown do
    Product.where(category: @category).delete_all
    @category.destroy
  end

  test "valid sourcing statuses accepted" do
    %w[pending approved rejected].each do |status|
      product = Product.new(asin: "VALID#{status}", category: @category, sourcing_status: status)
      assert product.valid?, "#{status} should be valid: #{product.errors.full_messages}"
    end
  end

  test "invalid sourcing status rejected" do
    product = Product.new(asin: 'INVALIDSS', category: @category, sourcing_status: 'unknown')
    assert_not product.valid?
    assert_includes product.errors[:sourcing_status], "is not included in the list"
  end

  test "valid shopify statuses accepted" do
    %w[pending publishing published synced failed].each do |status|
      product = Product.new(asin: "SHOPIFY#{status}", category: @category, shopify_status: status)
      assert product.valid?, "#{status} should be valid: #{product.errors.full_messages}"
    end
  end

  test "invalid shopify status rejected" do
    product = Product.new(asin: 'INVALIDSH', category: @category, shopify_status: 'bogus')
    assert_not product.valid?
  end

  test "price must be non-negative" do
    product = Product.new(asin: 'NEGPRICE1', category: @category, price: -5)
    assert_not product.valid?
    assert_includes product.errors[:price], "must be greater than or equal to 0"
  end

  test "nil price is allowed" do
    product = Product.new(asin: 'NILPRICE1', category: @category, price: nil)
    assert product.valid?
  end

  test "publishable? returns true when conditions met" do
    product = Product.new(asin: 'PUB00001', category: @category,
                          sourcing_status: 'approved', scraper_status: 'completed',
                          shopify_status: 'pending', title: 'Test', price: 29.99)
    assert product.publishable?
  end

  test "publishable? returns false when publishing" do
    product = Product.new(asin: 'PUB00002', category: @category,
                          sourcing_status: 'approved', scraper_status: 'completed',
                          shopify_status: 'publishing', title: 'Test', price: 29.99)
    assert_not product.publishable?
  end

  test "publishable? returns false without title" do
    product = Product.new(asin: 'PUB00003', category: @category,
                          sourcing_status: 'approved', scraper_status: 'completed',
                          shopify_status: 'pending', title: nil, price: 29.99)
    assert_not product.publishable?
  end

  test "publishable? returns false without price" do
    product = Product.new(asin: 'PUB00004', category: @category,
                          sourcing_status: 'approved', scraper_status: 'completed',
                          shopify_status: 'pending', title: 'Test', price: nil)
    assert_not product.publishable?
  end
end
