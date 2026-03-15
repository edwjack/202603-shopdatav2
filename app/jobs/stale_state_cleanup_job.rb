class StaleStateCleanupJob < ApplicationJob
  queue_as :default

  def perform
    # Reset categories stuck in 'sourcing' for > 2 hours
    stuck = Category.where(status: 'sourcing').where('updated_at < ?', 2.hours.ago)
    stuck_count = stuck.count
    stuck.each do |cat|
      cat.update!(status: 'tracking')
      Rails.logger.warn "[StaleStateCleanup] Reset category #{cat.name} from sourcing to tracking"
    end

    # Mark stale in_progress batches as failed
    stale_batches = SourcingBatch.where(status: 'in_progress').where('started_at < ?', 2.hours.ago)
    batch_count = stale_batches.count
    stale_batches.update_all(status: 'failed', completed_at: Time.current)

    Rails.logger.info "[StaleStateCleanup] Reset #{stuck_count} categories, #{batch_count} batches"
  end
end
