class ExcludedKeyword < ApplicationRecord
  self.sequence_name = "ISEQ$$_153265"

  validates :keyword, presence: true

  scope :active, -> { where(active: true) }
end
