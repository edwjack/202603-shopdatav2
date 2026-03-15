class ScrapeMetric < ApplicationRecord
  # Oracle IDENTITY column needs explicit sequence for bulk creates
  self.sequence_name = "ISEQ$$_158946"

  belongs_to :category, optional: true
  validates :collector_name, presence: true
  validates :run_date, presence: true

  scope :recent, -> { where('run_date >= ?', 7.days.ago) }
  scope :for_collector, ->(name) { where(collector_name: name) }
end
