class WeeklyTitleSyncJob < ApplicationJob
  queue_as :default

  def perform(category_id = nil)
    # Concurrent execution guard
    guard_key = category_id ? "title_sync_#{category_id}" : "title_sync_all"
    if Rails.cache.read(guard_key)
      Rails.logger.warn "[WeeklyTitleSyncJob] Already running#{category_id ? " for category #{category_id}" : ''}, skipping"
      return
    end
    Rails.cache.write(guard_key, true, expires_in: 30.minutes)

    begin
      result = PriceSyncService.sync(mode: :title, category_id: category_id)
      Rails.logger.info "[WeeklyTitleSyncJob] #{result.inspect}"
    ensure
      Rails.cache.delete(guard_key)
    end
  end
end
