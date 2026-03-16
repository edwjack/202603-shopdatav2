class ChunkedSourcingService
  CHUNK_SIZE = 500

  def self.process(category)
    asins = category.asin_urls.pending.pluck(:asin)
    return { total_chunks: 0, completed_chunks: 0, total_asins: 0 } if asins.empty?

    chunks = asins.each_slice(CHUNK_SIZE).to_a
    total_chunks = chunks.size
    completed_chunks = 0

    Rails.logger.info "[ChunkedSourcingService] #{category.name}: #{asins.size} ASINs → #{total_chunks} chunks"

    chunks.each_with_index do |chunk, idx|
      response = ScraperClientService.collect_async(
        '/scrape',
        { asins: chunk, category_id: category.id }
      )

      if response['error']
        Rails.logger.error "[ChunkedSourcingService] Chunk #{idx + 1}/#{total_chunks} failed: #{response['error']}"
      else
        completed_chunks += 1
        Rails.logger.info "[ChunkedSourcingService] Chunk #{idx + 1}/#{total_chunks} complete (#{chunk.size} ASINs)"
      end

      # Rate-limit between chunks, but skip sleep after the last chunk
      sleep(rand(180..300)) if idx < (total_chunks - 1)
    end

    { total_chunks: total_chunks, completed_chunks: completed_chunks, total_asins: asins.size }
  rescue => e
    Rails.logger.error "[ChunkedSourcingService] process failed for #{category.name}: #{e.message}"
    raise
  end
end
