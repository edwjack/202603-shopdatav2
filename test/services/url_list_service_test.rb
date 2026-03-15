require "test_helper"

class UrlListServiceTest < ActiveSupport::TestCase
  setup do
    ENV['MOCK_EXTERNAL_APIS'] = 'true'
    @category = Category.create!(name: 'Test URL Category', slug: 'pet-supplies', status: 'tracking', active: true)
  end

  teardown do
    AsinUrl.where(category: @category).delete_all
    @category.destroy
  end

  test "creates AsinUrl records from fixture" do
    result = UrlListService.collect(@category)
    assert result[:processed_count] > 0
    assert_equal result[:processed_count], result[:asin_count]
    assert AsinUrl.where(category: @category).count > 0
  end

  test "skips duplicates on second run" do
    UrlListService.collect(@category)
    first_count = AsinUrl.where(category: @category).count
    result = UrlListService.collect(@category)
    assert_equal 0, result[:processed_count]
    assert_equal first_count, AsinUrl.where(category: @category).count
  end
end
