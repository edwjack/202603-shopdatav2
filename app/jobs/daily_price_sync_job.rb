class DailyPriceSyncJob < ApplicationJob
  queue_as :default

  def perform
    result = PriceSyncService.sync(mode: :price)
    Rails.logger.info "[DailyPriceSyncJob] #{result.inspect}"
  end
end
