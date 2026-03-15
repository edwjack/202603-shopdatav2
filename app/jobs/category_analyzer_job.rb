class CategoryAnalyzerJob < ApplicationJob
  queue_as :default

  def perform
    analyzed = skipped = errors = 0
    Category.tracking.active.each do |category|
      result = CategoryAnalysisService.analyze(category)
      result.nil? ? skipped += 1 : analyzed += 1
    rescue CategoryAnalysisService::AnalysisError => e
      errors += 1
      Rails.logger.error "[CategoryAnalyzerJob] #{e.message}"
    end
    Rails.logger.info "[CategoryAnalyzerJob] Done: #{analyzed} analyzed, #{skipped} skipped, #{errors} errors"
  end
end
