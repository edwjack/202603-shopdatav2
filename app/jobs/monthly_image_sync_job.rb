class MonthlyImageSyncJob < ApplicationJob
  queue_as :default

  def perform
    result = ScraperClientService.rescrape_images
    Rails.logger.info "[MonthlyImageSyncJob] #{result.inspect}"
  end
end
