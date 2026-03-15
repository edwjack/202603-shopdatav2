require "test_helper"

class VectorSearchServiceTest < ActiveSupport::TestCase
  setup do
    ENV['MOCK_EXTERNAL_APIS'] = 'true'
  end

  test "mock mode returns recommendations excluding given category" do
    category = Category.tracking.active.first
    skip "No tracking+active category in DB" unless category

    results = VectorSearchService.find_similar(category: category, limit: 5)
    results.each do |rec|
      assert_not_equal category.id, rec.category_id, "Should exclude the given category"
    end
  end

  test "mock mode returns ordered by score desc" do
    category = Category.tracking.active.first
    skip "No tracking+active category in DB" unless category

    results = VectorSearchService.find_similar(category: category, limit: 5)
    return if results.size < 2
    scores = results.map(&:score)
    assert_equal scores, scores.sort.reverse, "Results should be ordered by score desc"
  end

  test "limit parameter is respected" do
    category = Category.tracking.active.first
    skip "No tracking+active category in DB" unless category

    results = VectorSearchService.find_similar(category: category, limit: 2)
    assert results.size <= 2
  end

  test "sanitize_sql_array is used for parameterized queries" do
    # Verify the SQL method uses parameterized queries (not string interpolation)
    source = File.read(Rails.root.join('app/services/vector_search_service.rb'))
    assert_includes source, 'sanitize_sql_array', "Must use sanitize_sql_array for SQL safety"
    # Extract only the SQL query lines (not logger/rescue lines)
    sql_lines = source.lines.select { |l| l.include?('SELECT') || l.include?('FROM') || l.include?('WHERE') }
    sql_lines.each do |line|
      assert_not_includes line, '#{', "SQL query must not use string interpolation: #{line.strip}"
    end
  end
end
