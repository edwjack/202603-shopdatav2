require "test_helper"

class ProductFilterServiceTest < ActiveSupport::TestCase
  setup do
    ENV['MOCK_EXTERNAL_APIS'] = 'true'
    @category = Category.create!(name: 'Test Filter Category', slug: 'test-filter', status: 'tracking', active: true)
  end

  teardown do
    Product.where(category: @category).delete_all
    ExcludedKeyword.where("keyword LIKE 'test_%'").delete_all
    @category.destroy
  end

  test "rejects product with price below 30" do
    Product.create!(asin: 'TFLTR00001', category: @category, title: 'Cheap Item', price: 15.00,
                    review_count: 50, review_rating: 4.5, sourcing_status: 'pending')
    result = ProductFilterService.filter(@category)
    assert_equal 0, result[:passed]
    assert_equal 1, result[:reasons][:price]
  end

  test "rejects product with price above 80" do
    Product.create!(asin: 'TFLTR00002', category: @category, title: 'Expensive Item', price: 99.99,
                    review_count: 50, review_rating: 4.5, sourcing_status: 'pending')
    result = ProductFilterService.filter(@category)
    assert_equal 0, result[:passed]
    assert_equal 1, result[:reasons][:price]
  end

  test "rejects product with excluded keyword in title" do
    ExcludedKeyword.create!(keyword: 'test_phone_case', active: true)
    Product.create!(asin: 'TFLTR00003', category: @category, title: 'Great test_phone_case Cover', price: 45.00,
                    review_count: 50, review_rating: 4.5, sourcing_status: 'pending')
    result = ProductFilterService.filter(@category)
    assert_equal 0, result[:passed]
    assert_equal 1, result[:reasons][:keyword]
  end

  test "rejects product with excluded keyword in category_name" do
    ExcludedKeyword.create!(keyword: 'test_electronics', active: true)
    Product.create!(asin: 'TFLTR00004', category: @category, title: 'Nice Gadget', price: 45.00,
                    category_name: 'test_electronics accessories', review_count: 50, review_rating: 4.5, sourcing_status: 'pending')
    result = ProductFilterService.filter(@category)
    assert_equal 0, result[:passed]
    assert_equal 1, result[:reasons][:keyword]
  end

  test "rejects gated brand" do
    Product.create!(asin: 'TFLTR00005', category: @category, title: 'Gated Product', brand: 'Apple', price: 45.00,
                    review_count: 50, review_rating: 4.5, sourcing_status: 'pending')
    result = ProductFilterService.filter(@category)
    assert_equal 0, result[:passed]
    assert_equal 1, result[:reasons][:brand]
  end

  test "rejects product with low review count" do
    Product.create!(asin: 'TFLTR00006', category: @category, title: 'Low Reviews Item', price: 45.00,
                    review_count: 5, review_rating: 4.5, sourcing_status: 'pending')
    result = ProductFilterService.filter(@category)
    assert_equal 0, result[:passed]
    assert_equal 1, result[:reasons][:reviews]
  end

  test "rejects product with low rating" do
    Product.create!(asin: 'TFLTR00007', category: @category, title: 'Bad Rating Item', price: 45.00,
                    review_count: 50, review_rating: 2.5, sourcing_status: 'pending')
    result = ProductFilterService.filter(@category)
    assert_equal 0, result[:passed]
    assert_equal 1, result[:reasons][:rating]
  end

  test "rejects product with hazard keyword" do
    Product.create!(asin: 'TFLTR00008', category: @category, title: 'ZZTEST FDA Certified ZZTEST Thingy', price: 45.00,
                    brand: 'ZZTestBrand', review_count: 50, review_rating: 4.5, sourcing_status: 'pending')
    result = ProductFilterService.filter(@category)
    assert_equal 0, result[:passed]
    assert_equal 1, result[:reasons][:hazard]
  end

  test "approves product passing all filters" do
    Product.create!(asin: 'TFLTR00009', category: @category, title: 'Great Pet Toy', brand: 'PetCo', price: 45.00,
                    review_count: 50, review_rating: 4.5, sourcing_status: 'pending')
    result = ProductFilterService.filter(@category)
    assert_equal 1, result[:passed]
    assert_equal 'approved', Product.find_by(asin: 'TFLTR00009').sourcing_status
  end

  test "returns processed_count as passed count" do
    Product.create!(asin: 'TFLTR00010', category: @category, title: 'Good Item', brand: 'GoodBrand', price: 50.00,
                    review_count: 100, review_rating: 4.8, sourcing_status: 'pending')
    result = ProductFilterService.filter(@category)
    assert_equal result[:passed], result[:processed_count]
  end
end
