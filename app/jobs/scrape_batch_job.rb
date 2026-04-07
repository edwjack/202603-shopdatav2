class ScrapeBatchJob < ApplicationJob
  queue_as :default

  POLL_INTERVAL = 30       # seconds between status polls
  TIMEOUT       = 2.hours  # max wait before giving up

  def perform(batch_id, asin_chunk)
    # POST to scraper microservice
    uri = URI("http://localhost:3211/scrape/batch")
    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = 60

    request = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
    request.body = { asins: asin_chunk, batch_id: batch_id }.to_json
    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.error "[ScrapeBatchJob] batch_id=#{batch_id} POST failed: #{response.code}"
      return
    end

    task_id = JSON.parse(response.body)["task_id"]
    deadline = Time.current + TIMEOUT

    # Poll until completed or timed out
    loop do
      if Time.current > deadline
        Rails.logger.error "[ScrapeBatchJob] batch_id=#{batch_id} task_id=#{task_id} timed out after 2h"
        break
      end

      sleep POLL_INTERVAL

      status_uri = URI("http://localhost:3211/status/#{task_id}")
      status_resp = Net::HTTP.get_response(status_uri)
      status_body = JSON.parse(status_resp.body)
      status = status_body["status"]

      Rails.logger.info "[ScrapeBatchJob] batch_id=#{batch_id} task_id=#{task_id} status=#{status}"

      if status == "completed"
        processed = status_body["processed_count"] || asin_chunk.size
        SourcingBatch.find(batch_id).update(processed_count: processed)

        ScrapeMetric.create!(
          batch_id: batch_id,
          task_id: task_id,
          asin_count: asin_chunk.size,
          processed_count: processed,
          completed_at: Time.current
        )
        break
      elsif status == "failed"
        Rails.logger.error "[ScrapeBatchJob] batch_id=#{batch_id} task_id=#{task_id} failed: #{status_body.inspect}"
        break
      end
    end
  end
end
