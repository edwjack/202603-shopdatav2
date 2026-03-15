class SourcingPipelineJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(category_id)
    category = Category.find(category_id)

    # Concurrent guard: skip if already sourcing
    if category.status == 'sourcing'
      Rails.logger.warn "[SourcingPipelineJob] Category #{category.name} already sourcing, skipping"
      return
    end

    category.update!(status: 'sourcing')

    run_phase(category, 'url_list') { UrlListService.collect(category) }
    run_phase(category, 'scrapling_collect') { ScraperClientService.collect_category(category) }
    run_phase(category, 'filter') { ProductFilterService.filter(category) }
    run_phase(category, 'final_filter') { FinalFilterService.filter(category) }

    category.update!(status: 'completed')
    Rails.logger.info "[SourcingPipelineJob] Pipeline complete for #{category.name}"
  rescue => e
    # Count consecutive failures in last 24h to determine retry vs permanent failure
    consecutive_failures = SourcingBatch.where(category: category, status: 'failed')
                             .where('created_at > ?', 24.hours.ago).count
    if consecutive_failures >= 2  # This rescue will be the 3rd failure
      category&.update(status: 'failed')
      Rails.logger.error "[SourcingPipeline] Category #{category&.name} marked failed after 3 consecutive failures"
    else
      category&.update(status: 'tracking')
      Rails.logger.warn "[SourcingPipeline] Category #{category&.name} reset to tracking for retry"
    end
    raise
  end

  private

  def run_phase(category, phase_name)
    # Clean up stale in_progress batches from previous failed runs
    SourcingBatch.where(category: category, phase: phase_name, status: 'in_progress')
                 .update_all(status: 'failed', completed_at: Time.current)

    batch = SourcingBatch.create_for_phase!(category, phase_name)
    result = yield
    batch.complete!(result[:processed_count], result[:total])
    Rails.logger.info "[SourcingPipelineJob] Phase #{phase_name}: #{result.inspect}"
  rescue => e
    batch&.fail!(e.message)
    raise
  end
end
