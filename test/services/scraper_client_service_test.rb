require "test_helper"

class ScraperClientServiceTest < ActiveSupport::TestCase
  setup do
    ENV['MOCK_EXTERNAL_APIS'] = 'true'
    @category = Category.create!(name: 'Pet Supplies', slug: 'test-scraper', status: 'tracking', active: true)
  end

  teardown do
    Product.where(category: @category).delete_all
    @category.destroy
  end

  test "mock mode creates products from unified fixture" do
    result = ScraperClientService.collect_category(@category)
    assert result[:processed_count] >= 1
    product = Product.where(category: @category).first
    assert_not_nil product
    assert_equal 'completed', product.scraper_status
    assert_not_nil product.scraping_synced_at
    assert_not_nil product.title
    assert_not_nil product.price
  end

  test "returns processed_count and total keys" do
    result = ScraperClientService.collect_category(@category)
    assert result.key?(:processed_count)
    assert result.key?(:total)
  end

  test "scrape_category alias works" do
    result = ScraperClientService.scrape_category(@category)
    assert result.key?(:processed_count)
  end

  test "field_completeness returns score and missing fields" do
    complete_product = {
      'title' => 'Widget', 'price' => 9.99, 'brand' => 'Acme',
      'review_rating' => 4.5, 'review_count' => 100,
      'about_this' => ['feature'], 'images' => ['url']
    }
    result = ScraperClientService.field_completeness(complete_product)
    assert_equal 100.0, result[:score]
    assert_empty result[:missing]
  end

  test "field_completeness detects missing fields" do
    partial_product = { 'title' => 'Widget', 'price' => 9.99 }
    result = ScraperClientService.field_completeness(partial_product)
    assert result[:score] < 100.0
    assert result[:missing].include?('brand')
  end

  test "validate_product_data filters blank titles and zero prices" do
    data = [
      { 'title' => 'Good Product', 'price' => 9.99 },
      { 'title' => '', 'price' => 9.99 },
      { 'title' => 'No Price', 'price' => 0 },
      { 'title' => nil, 'price' => 5.0 }
    ]
    valid = ScraperClientService.validate_product_data(data)
    assert_equal 1, valid.size
    assert_equal 'Good Product', valid.first['title']
  end

  test "health_check returns status hash" do
    result = ScraperClientService.health_check
    assert result.is_a?(Hash)
    assert result.key?('status')
  end
end
