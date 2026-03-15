class WeeklyTitleSyncJob < ApplicationJob
  queue_as :default

  def perform
    result = PriceSyncService.sync(mode: :title)
    Rails.logger.info "[WeeklyTitleSyncJob] #{result.inspect}"
  end
end
