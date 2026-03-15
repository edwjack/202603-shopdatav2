class AsinUrl < ApplicationRecord
  # Oracle IDENTITY column needs explicit sequence for bulk creates
  self.sequence_name = "ISEQ$$_153268"

  belongs_to :category

  validates :asin, presence: true

  scope :pending, -> { where(status: 'pending') }
  scope :collected, -> { where(status: 'collected') }
end
