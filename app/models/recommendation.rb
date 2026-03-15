class Recommendation < ApplicationRecord
  # VECTOR columns unsupported by ruby-oci8; use raw SQL for vector operations
  self.ignored_columns += [:insight_vector]
  self.sequence_name = "ISEQ$$_153237"

  belongs_to :category

  STATUSES = %w[pending approved rejected on_hold].freeze
  SCORE_METRICS = %w[demand_stability growth_momentum competition_landscape margin_potential cs_risk category_killer_fit].freeze

  validates :score, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 10 }
  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: 'pending') }
  scope :approved, -> { where(status: 'approved') }
  scope :rejected, -> { where(status: 'rejected') }
  scope :on_hold, -> { where(status: 'on_hold') }
  scope :this_week, -> { where("created_at >= ?", Time.current.beginning_of_week) }
  scope :for_week, ->(year_week) { where(week_number: year_week) }

  def score_breakdown_data
    return {} if score_breakdown.blank?
    JSON.parse(score_breakdown)
  rescue JSON::ParserError
    {}
  end

  def risks_data
    return [] if risks.blank?
    JSON.parse(risks)
  rescue JSON::ParserError
    []
  end

  def action_items_data
    return [] if action_items.blank?
    JSON.parse(action_items)
  rescue JSON::ParserError
    []
  end

  def analysis_input_data
    return {} if analysis_input.blank?
    JSON.parse(analysis_input)
  rescue JSON::ParserError
    {}
  end
end
