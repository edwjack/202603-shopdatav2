require "test_helper"

class WeeklyRecommendationDigestJobTest < ActiveSupport::TestCase
  test "runs without error" do
    assert_nothing_raised do
      WeeklyRecommendationDigestJob.perform_now
    end
  end

  test "uses YYYYWW format for year_week" do
    yw = CategoryAnalysisService.current_year_week
    assert yw >= 202001, "Should be YYYYWW format"
    assert_equal Date.current.strftime('%G%V').to_i, yw
  end
end
