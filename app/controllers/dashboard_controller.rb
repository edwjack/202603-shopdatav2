class DashboardController < ApplicationController
  def index
    @pending_count = Recommendation.pending.count
    @approved_count = Recommendation.approved.count
    @this_week_count = Recommendation.this_week.count
    @recent_recommendations = Recommendation.pending.order(created_at: :desc).limit(5).includes(:category)
    @categories_tracking = Category.tracking.active.count
    @categories_approved = Category.approved.count
    @total_products = Product.count
    @published_products = Product.published_shopify.count
    @total_categories = Category.active.count
    @shopify_stats = {
      published: Product.published_shopify.count,
      pending: Product.pending_shopify.count,
      failed: Product.where(shopify_status: 'failed').count
    }
    @recent_batches = SourcingBatch.order(created_at: :desc).limit(5).includes(:category)
    @active_pipelines = Category.sourcing.count

    # Scraping monitoring (B5)
    @scrape_trends = ScrapeMetric.where('run_date >= ?', 7.days.ago)
                                  .group(:collector_name)
                                  .select("collector_name, AVG(success_rate) as avg_success_rate, COUNT(*) as total_runs, SUM(failed) as total_failures")

    @data_freshness = Category.tracking.active.map do |cat|
      latest = cat.category_snapshots.order(snapshot_date: :desc).first
      {
        category: cat,
        last_snapshot: latest&.snapshot_date,
        age_hours: latest ? ((Time.current - latest.updated_at) / 1.hour).round(1) : nil,
        stale: latest.nil? || latest.updated_at < 48.hours.ago
      }
    end

    collector_names = %w[amazon_bsr movers_shakers google_trends social_signal competitor_monitor scraper_process]
    if defined?(CircuitBreaker)
      @scraper_status = CircuitBreaker.status('scraper_process')
      @scraping_status = collector_names.each_with_object({}) do |name, hash|
        hash[name] = CircuitBreaker.status(name)
      end
    else
      @scraper_status = { failures: 0, open: false, opened_at: nil }
      @scraping_status = collector_names.each_with_object({}) do |name, hash|
        hash[name] = { failures: 0, open: false, opened_at: nil }
      end
    end
  end
end
