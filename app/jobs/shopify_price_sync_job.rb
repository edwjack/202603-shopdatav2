class ShopifyPriceSyncJob < ApplicationJob
  queue_as :default

  def perform
    ShopifyPriceSyncService.sync
  end
end
