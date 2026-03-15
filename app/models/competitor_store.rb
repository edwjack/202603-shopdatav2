class CompetitorStore < ApplicationRecord
  self.sequence_name = "ISEQ$$_153271"

  validates :name, presence: true

  scope :active, -> { where(active: true) }
end
