class JobsController < ApplicationController
  def index
    @collection_jobs = [
      { name: 'Amazon BSR', job_class: 'AmazonBsrCollectorJob', last_at_key: :last_bsr_collected_at },
      { name: 'Movers & Shakers', job_class: 'MoversShakersCollectorJob', last_at_key: :last_movers_collected_at },
      { name: 'Google Trends', job_class: 'GoogleTrendsCollectorJob', last_at_key: :last_trends_collected_at },
      { name: 'Social Signals', job_class: 'SocialSignalCollectorJob', last_at_key: :last_social_collected_at },
      { name: 'Competitor Monitor', job_class: 'CompetitorMonitorJob', last_at_key: nil },
    ]
    @analysis_jobs = [
      { name: 'Category Analyzer', job_class: 'CategoryAnalyzerJob' },
      { name: 'Weekly Recommendation Digest', job_class: 'WeeklyRecommendationDigestJob' },
    ]
    @sync_jobs = [
      { name: 'Daily Price Sync', job_class: 'DailyPriceSyncJob' },
      { name: 'Weekly Title Sync', job_class: 'WeeklyTitleSyncJob' },
      { name: 'Monthly Image Sync', job_class: 'MonthlyImageSyncJob' },
      { name: 'Shopify Price Sync', job_class: 'ShopifyPriceSyncJob' },
    ]
    @sourcing_jobs = [
      { name: 'Sourcing Pipeline', job_class: 'SourcingPipelineJob', requires_category: true },
    ]
    @categories = Category.tracking.or(Category.where(status: 'completed')).order(:name)
    @recent_jobs = SolidQueue::Job.order(created_at: :desc).limit(20)
    @failed_job_ids = SolidQueue::FailedExecution.where(job_id: @recent_jobs.map(&:id)).pluck(:job_id, :error).to_h
  rescue ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished
    @recent_jobs = []
    @failed_job_ids = {}
  end

  ALLOWED_JOBS = %w[
    AmazonBsrCollectorJob
    MoversShakersCollectorJob
    GoogleTrendsCollectorJob
    SocialSignalCollectorJob
    CompetitorMonitorJob
    CategoryAnalyzerJob
    WeeklyRecommendationDigestJob
    SourcingPipelineJob
    DailyPriceSyncJob
    WeeklyTitleSyncJob
    MonthlyImageSyncJob
    ShopifyPriceSyncJob
  ].freeze

  def run
    job_class = params[:job_class]
    return redirect_to jobs_path, alert: "Invalid job class." unless ALLOWED_JOBS.include?(job_class)

    job = job_class.constantize
    if job == SourcingPipelineJob
      return redirect_to jobs_path, alert: "Category required for Sourcing Pipeline." if params[:category_id].blank?
      job.perform_later(params[:category_id].to_i)
    elsif params[:category_id].present?
      job.perform_later(params[:category_id].to_i)
    else
      job.perform_later
    end
    redirect_to jobs_path, notice: "#{job_class} enqueued."
  end
end
