require "test_helper"

class CategoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @category = Category.create!(name: 'Test Cat Edit', slug: "test-cat-edit-#{SecureRandom.hex(4)}", status: 'tracking', active: true, margin_rate: 50.0)
  end

  teardown do
    @category.reload.destroy rescue nil
  end

  test "index renders successfully" do
    get categories_path
    assert_response :success
  end

  test "show renders successfully" do
    get category_path(@category)
    assert_response :success
  end

  test "edit renders successfully" do
    get edit_category_path(@category)
    assert_response :success
  end

  test "update changes margin_rate" do
    patch category_path(@category), params: { category: { margin_rate: 65.5 } }
    assert_redirected_to category_path(@category)
    @category.reload
    assert_equal 65.5, @category.margin_rate.to_f
  end
end
