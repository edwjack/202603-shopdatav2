class Product < ApplicationRecord
  # VECTOR columns unsupported by ruby-oci8; use raw SQL for vector operations
  self.ignored_columns += [:title_vector]
  # Oracle IDENTITY column needs explicit sequence for bulk creates
  self.sequence_name = "ISEQ$$_153252"

  GATED_BRANDS = %w[Apple Nike Samsung Sony Bose Nintendo PlayStation Xbox Canon Nikon Dyson KitchenAid Vitamix].freeze

  belongs_to :category, optional: true

  validates :asin, presence: true, uniqueness: true
  validates :sourcing_status, inclusion: { in: %w[pending approved rejected] }, allow_nil: true
  validates :scraper_status, inclusion: { in: %w[pending completed failed] }, allow_nil: true
  validates :shopify_status, inclusion: { in: %w[pending publishing published synced failed] }, allow_nil: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  scope :pending_sourcing, -> { where(sourcing_status: 'pending') }
  scope :approved_sourcing, -> { where(sourcing_status: 'approved') }
  scope :rejected_sourcing, -> { where(sourcing_status: 'rejected') }

  scope :filtered, -> { where(sourcing_status: 'approved') }
  scope :needs_scraping, -> { where(sourcing_status: 'approved', scraper_status: [nil, 'pending']) }

  scope :pending_scrape, -> { where(scraper_status: 'pending') }
  scope :scraped, -> { where(scraper_status: 'completed') }
  scope :scrape_failed, -> { where(scraper_status: 'failed') }

  # NULL-safe sync scopes
  scope :needs_price_sync, -> {
    where(sourcing_status: 'approved')
      .where("data_synced_at IS NULL OR data_synced_at < ?", Date.current - 1)
  }
  scope :needs_image_sync, -> {
    where(sourcing_status: 'approved')
      .where("scraping_synced_at IS NULL OR scraping_synced_at < ?", Date.current - 30)
  }

  scope :pending_shopify, -> { where(shopify_status: 'pending') }
  scope :published_shopify, -> { where(shopify_status: 'published') }
  scope :synced_shopify, -> { where(shopify_status: 'synced') }

  scope :in_price_range, -> { where(price: 30..80) }
  scope :publishable, -> { where(sourcing_status: 'approved', scraper_status: 'completed').where.not(shopify_status: 'publishing') }

  # CLOB JSON helpers — safe parse with fallback
  def about_this_data
    return [] if about_this.blank?
    JSON.parse(about_this)
  rescue JSON::ParserError
    []
  end

  def tags_data
    return [] if tags.blank?
    JSON.parse(tags)
  rescue JSON::ParserError
    []
  end

  def images_data
    return [] if images.blank?
    JSON.parse(images)
  rescue JSON::ParserError
    []
  end

  def overview_data
    return [] if overview.blank?
    JSON.parse(overview)
  rescue JSON::ParserError
    []
  end

  def options_data
    return {} if options.blank?
    JSON.parse(options)
  rescue JSON::ParserError
    {}
  end

  def publishable?
    sourcing_status == 'approved' && scraper_status == 'completed' &&
      shopify_status != 'publishing' && title.present? && price.present?
  end
end
