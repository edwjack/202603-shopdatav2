class CategorySnapshot < ApplicationRecord
  self.sequence_name = "ISEQ$$_153228"

  belongs_to :category

  validates :snapshot_date, presence: true

  scope :recent, -> { order(snapshot_date: :desc) }
  scope :for_period, ->(days) { where("snapshot_date >= ?", days.days.ago) }

  def movers_data_parsed
    return {} if movers_data.blank?
    JSON.parse(movers_data)
  rescue JSON::ParserError
    {}
  end

  def competitor_data_parsed
    return {} if competitor_data.blank?
    JSON.parse(competitor_data)
  rescue JSON::ParserError
    {}
  end
end
