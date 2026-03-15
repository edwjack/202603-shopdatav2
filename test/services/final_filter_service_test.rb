require "test_helper"

class FinalFilterServiceTest < ActiveSupport::TestCase
  setup do
    ENV['MOCK_EXTERNAL_APIS'] = 'true'
    @category = Category.create!(name: 'Test Final Filter Category', slug: 'test-final', status: 'tracking', active: true)
  end

  teardown do
    Product.where(category: @category).delete_all
    @category.destroy
  end

  test "rejects product with quantity below 3" do
    Product.create!(asin: 'TFFLT00001', category: @category, title: 'Low Stock',
                    sourcing_status: 'approved', scraper_status: 'completed', quantity: 1,
                    images: '["img.jpg"]', about_this: '["Feature 1"]')
    result = FinalFilterService.filter(@category)
    assert_equal 0, result[:passed]
    assert_equal 1, result[:reasons][:quantity]
  end

  test "rejects product with empty images" do
    Product.create!(asin: 'TFFLT00002', category: @category, title: 'No Images',
                    sourcing_status: 'approved', scraper_status: 'completed', quantity: 10,
                    images: '[]', about_this: '["Feature 1"]')
    result = FinalFilterService.filter(@category)
    assert_equal 0, result[:passed]
    assert_equal 1, result[:reasons][:images]
  end

  test "rejects product with empty about_this" do
    Product.create!(asin: 'TFFLT00003', category: @category, title: 'No Features',
                    sourcing_status: 'approved', scraper_status: 'completed', quantity: 10,
                    images: '["img.jpg"]', about_this: '[]')
    result = FinalFilterService.filter(@category)
    assert_equal 0, result[:passed]
    assert_equal 1, result[:reasons][:features]
  end

  test "keeps approved product with good data" do
    Product.create!(asin: 'TFFLT00004', category: @category, title: 'Good Product',
                    sourcing_status: 'approved', scraper_status: 'completed', quantity: 10,
                    images: '["img1.jpg", "img2.jpg"]', about_this: '["Feature 1", "Feature 2"]')
    result = FinalFilterService.filter(@category)
    assert_equal 1, result[:passed]
    assert_equal 'approved', Product.find_by(asin: 'TFFLT00004').sourcing_status
  end

  test "uses about_this_data helper to handle string edge cases" do
    Product.create!(asin: 'TFFLT00005', category: @category, title: 'Edge Case',
                    sourcing_status: 'approved', scraper_status: 'completed', quantity: 10,
                    images: '["img.jpg"]', about_this: nil)
    result = FinalFilterService.filter(@category)
    assert_equal 0, result[:passed]
    assert_equal 1, result[:reasons][:features]
  end
end
