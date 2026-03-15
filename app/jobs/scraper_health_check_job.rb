class ScraperHealthCheckJob < ApplicationJob
  queue_as :default

  def perform
    health = ScraperClientService.health_check
    if health.is_a?(Hash) && health['status'] == 'ok'
      CircuitBreaker.record_success('scraper_process')
      Rails.logger.debug "[ScraperHealthCheck] Scraper healthy"
    else
      CircuitBreaker.record_failure('scraper_process')
      Rails.logger.error "[ScraperHealthCheck] Scraper unhealthy: #{health.inspect}"
    end
  rescue => e
    CircuitBreaker.record_failure('scraper_process')
    Rails.logger.error "[ScraperHealthCheck] Scraper unreachable: #{e.message}"
  end
end
