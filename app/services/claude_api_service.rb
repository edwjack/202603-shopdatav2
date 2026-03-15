require 'net/http'
require 'json'

class ClaudeApiService
  API_URL = "https://api.anthropic.com/v1/messages"
  DEFAULT_MODEL = "claude-opus-4-6"
  MAX_TOKENS = 4096

  class ApiError < StandardError; end

  def self.analyze(system_prompt:, user_prompt:, model: DEFAULT_MODEL)
    return mock_response if MockDataService.mock_mode?

    api_key = ENV['ANTHROPIC_API_KEY']
    raise ApiError, "ANTHROPIC_API_KEY not set" if api_key.blank?

    uri = URI(API_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 120
    http.open_timeout = 30

    request = Net::HTTP::Post.new(uri.path)
    request['Content-Type'] = 'application/json'
    request['x-api-key'] = api_key
    request['anthropic-version'] = '2023-06-01'
    request.body = {
      model: model, max_tokens: MAX_TOKENS, system: system_prompt,
      messages: [{ role: "user", content: user_prompt }]
    }.to_json

    response = http.request(request)
    raise ApiError, "Claude API error: #{response.code} - #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    result = JSON.parse(response.body)
    content_text = result.dig('content', 0, 'text')
    raise ApiError, "Empty response from Claude API" if content_text.blank?

    json_text = extract_json(content_text)
    JSON.parse(json_text)
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    raise ApiError, "Claude API timeout: #{e.message}"
  rescue JSON::ParserError => e
    raise ApiError, "Failed to parse Claude response: #{e.message}"
  end

  private

  def self.mock_response
    MockDataService.load('claude_analysis_sample')
  end

  def self.extract_json(text)
    text =~ /```(?:json)?\s*\n?(.*?)\n?```/m ? $1.strip : text.strip
  end
end
