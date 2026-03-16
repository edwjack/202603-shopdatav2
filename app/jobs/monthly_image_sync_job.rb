class MonthlyImageSyncJob < ApplicationJob
  queue_as :default

  def perform(category_id = nil)
    # Concurrent execution guard
    guard_key = category_id ? "image_sync_#{category_id}" : "image_sync_all"
    if Rails.cache.read(guard_key)
      Rails.logger.warn "[MonthlyImageSyncJob] Already running#{category_id ? " for category #{category_id}" : ''}, skipping"
      return
    end
    Rails.cache.write(guard_key, true, expires_in: 30.minutes)

    begin
      result = ScraperClientService.rescrape_images(category_id: category_id)
      Rails.logger.info "[MonthlyImageSyncJob] #{result.inspect}"
    ensure
      Rails.cache.delete(guard_key)
    end
  end
end
