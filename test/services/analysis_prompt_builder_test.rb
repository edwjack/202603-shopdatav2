require "test_helper"

class AnalysisPromptBuilderTest < ActiveSupport::TestCase
  test "system prompt contains FRD business context" do
    prompt = AnalysisPromptBuilder.system_prompt
    assert_includes prompt, 'dropshipping'
    assert_includes prompt, 'Shopify'
    assert_includes prompt, '$30-80'
    assert_includes prompt, 'score_breakdown'
    assert_includes prompt, 'demand_stability'
    assert_includes prompt, 'category_killer_fit'
  end

  test "build_user_prompt returns valid JSON with all data sources" do
    category = Category.tracking.active.first
    skip "No tracking+active category in DB" unless category

    snapshot = category.category_snapshots.order(snapshot_date: :desc).first
    skip "No snapshot for category" unless snapshot

    json_str = AnalysisPromptBuilder.build_user_prompt(
      category: category, snapshot: snapshot, similar_recommendations: []
    )
    parsed = JSON.parse(json_str)

    assert parsed.key?('category'), "Missing category"
    assert parsed.key?('amazon_data'), "Missing amazon_data"
    assert parsed.key?('google_trends'), "Missing google_trends"
    assert parsed.key?('social'), "Missing social"
    assert parsed.key?('competitor'), "Missing competitor"
    assert parsed.key?('similar_historical'), "Missing similar_historical"
  end

  test "build_user_prompt includes amazon sub-fields" do
    category = Category.tracking.active.first
    skip "No tracking+active category in DB" unless category

    snapshot = category.category_snapshots.order(snapshot_date: :desc).first
    skip "No snapshot for category" unless snapshot

    parsed = JSON.parse(
      AnalysisPromptBuilder.build_user_prompt(
        category: category, snapshot: snapshot, similar_recommendations: []
      )
    )
    amazon = parsed['amazon_data']
    %w[top100_avg_bsr avg_price avg_reviews fba_ratio].each do |field|
      assert amazon.key?(field), "amazon_data missing #{field}"
    end
  end
end
