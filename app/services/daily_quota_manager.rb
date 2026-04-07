class DailyQuotaManager
  CHUNK_SIZE = 500

  def self.run(sourcing_batch_id, daily_limit: 5000)
    # Query remaining ASINs from scraper checkpoint
    uri = URI("http://localhost:3211/checkpoint/#{sourcing_batch_id}/remaining")
    response = Net::HTTP.get_response(uri)

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.error "[DailyQuotaManager] Failed to fetch remaining for batch #{sourcing_batch_id}: #{response.code}"
      return { remaining: 0, queued: 0, chunks: 0 }
    end

    body = JSON.parse(response.body)
    remaining_asins = body["remaining_asins"] || []
    remaining_count = remaining_asins.size

    if remaining_count == 0
      SourcingBatch.find(sourcing_batch_id).update(status: "completed", completed_at: Time.current)
      Rails.logger.info "[DailyQuotaManager] batch #{sourcing_batch_id} complete — no remaining ASINs"
      return { remaining: 0, queued: 0, chunks: 0 }
    end

    to_process = remaining_asins.first([remaining_count, daily_limit].min)
    chunks = to_process.each_slice(CHUNK_SIZE).to_a

    chunks.each do |chunk|
      ScrapeBatchJob.perform_later(sourcing_batch_id, chunk)
    end

    Rails.logger.info "[DailyQuotaManager] batch #{sourcing_batch_id}: #{remaining_count} remaining, queued #{to_process.size} in #{chunks.size} chunks"

    { remaining: remaining_count, queued: to_process.size, chunks: chunks.size }
  end
end
