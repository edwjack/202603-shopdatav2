class ShopifyPriceSyncJob < ApplicationJob
  queue_as :default

  def perform(category_id = nil)
    # Concurrent execution guard
    guard_key = category_id ? "shopify_price_sync_#{category_id}" : "shopify_price_sync_all"
    if Rails.cache.read(guard_key)
      Rails.logger.warn "[ShopifyPriceSyncJob] Already running#{category_id ? " for category #{category_id}" : ''}, skipping"
      return
    end
    Rails.cache.write(guard_key, true, expires_in: 30.minutes)

    begin
      ShopifyPriceSyncService.sync(category_id: category_id)
    ensure
      Rails.cache.delete(guard_key)
    end
  end
end
