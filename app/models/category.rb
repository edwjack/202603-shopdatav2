class Category < ApplicationRecord
  self.sequence_name = "ISEQ$$_153221"

  has_many :category_snapshots, dependent: :destroy
  has_many :recommendations, dependent: :destroy
  has_many :products
  has_many :asin_urls, dependent: :destroy
  has_many :sourcing_batches, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :amazon_node_id, length: { maximum: 50 }, allow_blank: true

  scope :tracking, -> { where(status: 'tracking') }
  scope :approved, -> { where(status: 'approved') }
  scope :sourcing, -> { where(status: 'sourcing') }
  scope :completed, -> { where(status: 'completed') }
  scope :active, -> { where(active: true) }
end
