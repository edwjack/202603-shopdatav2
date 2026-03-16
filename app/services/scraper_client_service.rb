require 'net/http'

class ScraperClientService
  SCRAPER_URL = "http://127.0.0.1:#{ENV.fetch('SCRAPER_PORT', '3211')}".freeze
  POLL_INTERVAL = 10 # seconds
  TIMEOUT = ENV.fetch('SCRAPER_TIMEOUT_SECONDS', '1800').to_i # 30 min default

  EXPECTED_PRODUCT_FIELDS = %w[title price brand review_rating review_count about_this images].freeze

  # M7: Unified collect (replaces pa_api + scrape phases)
  def self.collect_category(category)
    if MockDataService.mock_mode?
      collect_mock(category)
    else
      collect_real(category)
    end
  end

  # Legacy: still used by MonthlyImageSyncJob
  def self.scrape_category(category)
    collect_category(category)
  end

  def self.rescrape_images
    scrape_mock_for_sync
  end

  # Generic sync request to a scraper endpoint (for BSR, Movers, Trends, Social)
  def self.collect_sync(path, params, timeout: 60, correlation_id: nil)
    correlation_id ||= SecureRandom.uuid
    uri = URI("#{SCRAPER_URL}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = timeout
    request = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
    request['X-Correlation-ID'] = correlation_id
    request.body = params.to_json
    response = http.request(request)
    JSON.parse(response.body)
  rescue => e
    Rails.logger.error "[ScraperClient] #{path} failed: #{e.message} (correlation_id=#{correlation_id})"
    { 'error' => e.message }
  end

  # Generic async request: POST to start task, poll /status/{task_id} until complete
  def self.collect_async(path, params, timeout: TIMEOUT, correlation_id: nil)
    correlation_id ||= SecureRandom.uuid
    response = collect_sync(path, params, timeout: 30, correlation_id: correlation_id)
    return response if response['error']

    task_id = response['task_id']
    return { 'error' => 'No task_id returned' } unless task_id

    poll_task_status(task_id, timeout: timeout)
  end

  # Field completeness scoring for product data quality
  def self.field_completeness(product_data)
    present = EXPECTED_PRODUCT_FIELDS.count { |f| product_data[f].present? }
    score = (present.to_f / EXPECTED_PRODUCT_FIELDS.size * 100).round(1)
    missing = EXPECTED_PRODUCT_FIELDS.select { |f| product_data[f].blank? }
    { score: score, missing: missing }
  end

  # Data quality gate — reject blank titles and zero prices
  def self.validate_product_data(data)
    data.select { |p| p['title'].present? && p['price'].to_f > 0 }
  end

  def self.health_check
    uri = URI("#{SCRAPER_URL}/health")
    response = Net::HTTP.get_response(uri)
    JSON.parse(response.body)
  rescue Errno::ECONNREFUSED, Errno::ECONNRESET, SocketError => e
    { 'status' => 'unavailable', 'error' => e.message }
  end

  private

  def self.collect_mock(category)
    data = MockDataService.load('scrapling_collect_sample')
    completed = 0

    data.each do |item|
      next unless item['category_id'] == category.id || item['category_name'] == category.name

      product = Product.find_or_initialize_by(asin: item['asin'])
      product.assign_attributes(
        title: item['title'],
        brand: item['brand'],
        price: item['price'],
        about_this: item['about_this'].to_json,
        tags: item['tags'].to_json,
        review_rating: item['review_rating'],
        review_count: item['review_count'],
        category_name: item['category_name'],
        category: category,
        images: item['images'].to_json,
        overview: item['overview'].to_json,
        options: item['options'].to_json,
        quantity: item['quantity'],
        scraper_status: 'completed',
        scraping_synced_at: Time.current,
        sourcing_status: product.sourcing_status || 'pending'
      )
      product.save!
      completed += 1
    rescue => e
      Rails.logger.error "[ScraperClientService] Failed to upsert #{item['asin']}: #{e.message}"
    end

    { processed_count: completed, total: completed }
  end

  def self.collect_real(category)
    asins = category.asin_urls.pending.pluck(:asin)
    return { processed_count: 0, total: 0 } if asins.empty?

    response = collect_async('/scrape', { asins: asins, category_id: category.id })
    return { processed_count: 0, total: asins.size } if response['error']

    results = response['results'] || []

    # Data quality gate
    valid_results = validate_product_data(results)
    invalid_count = results.size - valid_results.size
    if invalid_count > 0
      Rails.logger.warn "[ScraperClientService] Quality gate rejected #{invalid_count}/#{results.size} items for #{category.slug}"
    end

    # Field completeness warning
    if valid_results.any?
      avg_completeness = valid_results.sum { |r| field_completeness(r)[:score] } / valid_results.size
      if avg_completeness < 70
        Rails.logger.warn "[ScraperClientService] Low field completeness #{avg_completeness.round(1)}% for #{category.slug}"
      end
    end

    completed = 0
    valid_results.each do |item|
      next unless item['asin'].present?
      product = Product.find_or_initialize_by(asin: item['asin'])
      product.assign_attributes(
        title: item['title'],
        brand: item['brand'],
        price: item['price'],
        about_this: (item['about_this'] || []).to_json,
        tags: (item['tags'] || []).to_json,
        review_rating: item['review_rating'],
        review_count: item['review_count'],
        category_name: item['category_name'],
        category: category,
        images: (item['images'] || []).to_json,
        overview: (item['overview'] || []).to_json,
        options: (item['options'] || {}).to_json,
        quantity: item['quantity'],
        scraper_status: 'completed',
        scraping_synced_at: Time.current,
        sourcing_status: product.sourcing_status || 'pending'
      )
      product.save!
      completed += 1
    rescue => e
      Rails.logger.error "[ScraperClientService] Failed to upsert #{item['asin']}: #{e.message}"
    end

    category.asin_urls.pending.update_all(status: 'collected', collected_at: Time.current)
    { processed_count: completed, total: asins.size }
  rescue Errno::ECONNREFUSED => e
    Rails.logger.error "[ScraperClientService] Scraper not running: #{e.message}"
    { processed_count: 0, total: 0 }
  end

  def self.scrape_mock_for_sync
    products = Product.needs_image_sync
    count = products.count
    products.update_all(scraping_synced_at: Time.current)
    { processed_count: count, completed: count, failed: 0 }
  end

  def self.poll_task_status(task_id, timeout: TIMEOUT)
    start_time = Time.current
    loop do
      sleep(POLL_INTERVAL)
      status = fetch_task_status(task_id)
      return status if status['status'] == 'completed' || status['status'] == 'failed' || status['error']
      if Time.current - start_time > timeout
        Rails.logger.error "[ScraperClientService] Timeout polling task #{task_id}"
        return { 'error' => 'timeout', 'results' => [] }
      end
    end
  rescue => e
    Rails.logger.error "[ScraperClientService] poll_task_status failed: #{e.message}"
    { 'error' => e.message, 'results' => [] }
  end

  def self.fetch_task_status(task_id)
    uri = URI("#{SCRAPER_URL}/status/#{task_id}")
    response = Net::HTTP.get_response(uri)
    JSON.parse(response.body)
  rescue => e
    Rails.logger.error "[ScraperClientService] fetch_task_status failed for task #{task_id}: #{e.message}"
    { 'error' => e.message, 'status' => 'error' }
  end
end
