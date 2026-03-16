class CategoryAnalyzerJob < ApplicationJob
  queue_as :default

  def perform(category_id = nil)
    analyzed = skipped = errors = 0

    categories = if category_id
      [Category.find(category_id)]
    else
      Category.tracking.active.to_a
    end

    categories.each do |category|
      # Concurrent execution guard
      guard_key = "analyzing_#{category.id}"
      if Rails.cache.read(guard_key)
        Rails.logger.warn "[CategoryAnalyzerJob] Already running for #{category.slug}, skipping"
        skipped += 1
        next
      end
      Rails.cache.write(guard_key, true, expires_in: 30.minutes)

      begin
        result = CategoryAnalysisService.analyze(category)
        result.nil? ? skipped += 1 : analyzed += 1
      rescue CategoryAnalysisService::AnalysisError => e
        errors += 1
        Rails.logger.error "[CategoryAnalyzerJob] #{e.message}"
      ensure
        Rails.cache.delete(guard_key)
      end
    end

    Rails.logger.info "[CategoryAnalyzerJob] Done: #{analyzed} analyzed, #{skipped} skipped, #{errors} errors"
  end
end
