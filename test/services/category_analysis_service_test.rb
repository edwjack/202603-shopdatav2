require "test_helper"

class CategoryAnalysisServiceTest < ActiveSupport::TestCase
  setup do
    ENV['MOCK_EXTERNAL_APIS'] = 'true'
  end

  test "current_year_week returns YYYYWW format" do
    yw = CategoryAnalysisService.current_year_week
    assert yw >= 202001, "Should be YYYYWW format, got #{yw}"
    assert yw <= 210053, "Should be YYYYWW format, got #{yw}"
    assert_equal Date.current.strftime('%G%V').to_i, yw
  end

  test "analyze creates recommendation for category with recent snapshot" do
    category = Category.tracking.active.first
    skip "No tracking+active category in DB" unless category

    snapshot = category.category_snapshots
                       .where("snapshot_date >= ?", Date.current - 7)
                       .order(snapshot_date: :desc).first
    skip "No recent snapshot" unless snapshot

    rec = CategoryAnalysisService.analyze(category)
    assert rec.is_a?(Recommendation)
    assert rec.persisted?
    assert rec.score.between?(0, 10)
    assert_equal CategoryAnalysisService.current_year_week, rec.week_number
    assert_equal 'pending', rec.status
    assert rec.insight.present?
    assert rec.model_version.present?
  end

  test "analyze skips categories without recent snapshots" do
    category = Category.tracking.active.first
    skip "No tracking+active category in DB" unless category

    # Check if any exist beyond 7 days
    old_count = category.category_snapshots.where("snapshot_date < ?", Date.current - 7).count
    recent_count = category.category_snapshots.where("snapshot_date >= ?", Date.current - 7).count

    if recent_count > 0
      # There are recent snapshots, so analyze should NOT return nil
      result = CategoryAnalysisService.analyze(category)
      assert_not_nil result
    else
      result = CategoryAnalysisService.analyze(category)
      assert_nil result
    end
  end

  test "analyze deduplicates by YYYYWW week number" do
    category = Category.tracking.active.first
    skip "No tracking+active category in DB" unless category

    snapshot = category.category_snapshots
                       .where("snapshot_date >= ?", Date.current - 7)
                       .order(snapshot_date: :desc).first
    skip "No recent snapshot" unless snapshot

    rec1 = CategoryAnalysisService.analyze(category)
    rec2 = CategoryAnalysisService.analyze(category)

    assert_equal rec1.id, rec2.id, "Should update same record within same week"
    assert_equal CategoryAnalysisService.current_year_week, rec1.week_number
  end

  test "validate_response rejects missing keys" do
    bad_result = { 'score' => 5 }
    assert_raises(CategoryAnalysisService::AnalysisError) do
      CategoryAnalysisService.send(:validate_response!, bad_result)
    end
  end

  test "validate_response rejects out of range score" do
    result = MockDataService.load('claude_analysis_sample').merge('score' => 15)
    assert_raises(CategoryAnalysisService::AnalysisError) do
      CategoryAnalysisService.send(:validate_response!, result)
    end
  end
end
