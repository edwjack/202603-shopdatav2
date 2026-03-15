require "test_helper"

class ClaudeApiServiceTest < ActiveSupport::TestCase
  setup do
    ENV['MOCK_EXTERNAL_APIS'] = 'true'
  end

  test "mock mode returns valid fixture data" do
    result = ClaudeApiService.analyze(system_prompt: "test", user_prompt: "test")
    assert result.is_a?(Hash)
    assert_includes result.keys, 'score'
    assert_includes result.keys, 'score_breakdown'
    assert_includes result.keys, 'insight'
    assert_includes result.keys, 'risks'
    assert_includes result.keys, 'action_items'
    assert_includes result.keys, 'similar_pattern'
  end

  test "mock response has valid score range" do
    result = ClaudeApiService.analyze(system_prompt: "test", user_prompt: "test")
    assert result['score'].to_f.between?(0, 10)
  end

  test "mock response has all 6 score metrics" do
    result = ClaudeApiService.analyze(system_prompt: "test", user_prompt: "test")
    metrics = %w[demand_stability growth_momentum competition_landscape margin_potential cs_risk category_killer_fit]
    metrics.each do |key|
      assert result['score_breakdown'].key?(key), "Missing metric: #{key}"
      assert result['score_breakdown'][key].key?('score'), "#{key} missing score"
      assert result['score_breakdown'][key].key?('reason'), "#{key} missing reason"
    end
  end

  test "extract_json strips markdown code fences" do
    wrapped = "```json\n{\"score\": 5}\n```"
    extracted = ClaudeApiService.send(:extract_json, wrapped)
    assert_equal '{"score": 5}', extracted
  end

  test "extract_json passes through plain JSON" do
    plain = '{"score": 5}'
    extracted = ClaudeApiService.send(:extract_json, plain)
    assert_equal '{"score": 5}', extracted
  end
end
