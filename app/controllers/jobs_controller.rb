class JobsController < ApplicationController
  def index
    @collectors = [
      { name: 'Amazon BSR', job_class: 'AmazonBsrCollectorJob', schedule: 'Daily 2am' },
      { name: 'Movers & Shakers', job_class: 'MoversShakersCollectorJob', schedule: 'Daily 4am' },
      { name: 'Google Trends', job_class: 'GoogleTrendsCollectorJob', schedule: 'Weekly Mon 3am' },
      { name: 'Social Signals', job_class: 'SocialSignalCollectorJob', schedule: 'Weekly Wed 3am' },
      { name: 'Competitor Monitor', job_class: 'CompetitorMonitorJob', schedule: 'Weekly Fri 3am' },
    ]
    @ai_jobs = [
      { name: 'Category Analyzer', job_class: 'CategoryAnalyzerJob', schedule: 'Daily 6am' },
      { name: 'Weekly Recommendation Digest', job_class: 'WeeklyRecommendationDigestJob', schedule: 'Weekly Mon 9am' },
    ]
    @sourcing_jobs = [
      { name: 'Sourcing Pipeline', job_class: 'SourcingPipelineJob', schedule: 'On approval', needs_category: true },
    ]
    @sync_jobs = [
      { name: 'Daily Price Sync', job_class: 'DailyPriceSyncJob', schedule: 'Daily 8am' },
      { name: 'Weekly Title Sync', job_class: 'WeeklyTitleSyncJob', schedule: 'Weekly Sun 2am' },
      { name: 'Monthly Image Sync', job_class: 'MonthlyImageSyncJob', schedule: 'Monthly 1st 2am' },
    ]
    @shopify_jobs = [
      { name: 'Shopify Price Sync', job_class: 'ShopifyPriceSyncJob', schedule: 'Daily 10am' },
    ]
    @categories = Category.tracking.or(Category.where(status: 'completed'))
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
    else
      job.perform_later
    end
    redirect_to jobs_path, notice: "#{job_class} enqueued."
  end
end
