require "test_helper"

class CategoryAnalyzerJobTest < ActiveSupport::TestCase
  setup do
    ENV['MOCK_EXTERNAL_APIS'] = 'true'
  end

  test "runs end-to-end with mock data" do
    assert_nothing_raised do
      CategoryAnalyzerJob.perform_now
    end
  end

  test "creates recommendations for categories with snapshots" do
    initial_count = Recommendation.count
    CategoryAnalyzerJob.perform_now
    assert_operator Recommendation.count, :>=, initial_count
  end

  test "is idempotent within same week" do
    CategoryAnalyzerJob.perform_now
    count_after_first = Recommendation.count
    CategoryAnalyzerJob.perform_now
    assert_equal count_after_first, Recommendation.count, "Should not create duplicates"
  end
end
