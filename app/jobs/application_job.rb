class ApplicationJob < ActiveJob::Base
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  around_perform do |job, block|
    Rails.logger.info "[#{job.class.name}] Started at #{Time.current}"
    block.call
    Rails.logger.info "[#{job.class.name}] Completed at #{Time.current}"
  rescue => e
    Rails.logger.error "[#{job.class.name}] Failed: #{e.message}"
    raise
  end
end
