class SourcingBatch < ApplicationRecord
  # Oracle IDENTITY column needs explicit sequence for bulk creates
  self.sequence_name = "ISEQ$$_153274"

  belongs_to :category

  PHASES = %w[url_list scrapling_collect filter final_filter].freeze
  STATUSES = %w[pending in_progress completed failed].freeze

  validates :phase, inclusion: { in: PHASES }
  validates :status, inclusion: { in: STATUSES }

  def self.create_for_phase!(category, phase)
    create!(category: category, phase: phase, status: 'in_progress', started_at: Time.current)
  end

  def complete!(count, total = nil)
    update!(status: 'completed', processed_count: count,
            total_count: total || count, completed_at: Time.current)
  end

  def fail!(error_msg = nil)
    update!(status: 'failed', completed_at: Time.current)
    Rails.logger.error "[SourcingBatch] Phase #{phase} failed for category #{category_id}: #{error_msg}"
  end

  def progress_percentage
    return 0 if total_count.nil? || total_count.zero?
    ((processed_count.to_f / total_count) * 100).round(1)
  end
end
