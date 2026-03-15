class RecommendationsController < ApplicationController
  def index
    @status = params[:status] || 'pending'
    @recommendations = Recommendation.includes(:category).order(created_at: :desc)
    @recommendations = @recommendations.where(status: @status) unless @status == 'all'
    @this_week_count = Recommendation.this_week.count
    @pending_count = Recommendation.pending.count
  end

  def show
    @recommendation = Recommendation.find(params[:id])
    @category = @recommendation.category
  end

  def approve
    @recommendation = Recommendation.find(params[:id])
    @recommendation.update!(status: 'approved')
    SourcingPipelineJob.perform_later(@recommendation.category_id)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to recommendations_path, notice: "Recommendation approved." }
    end
  end

  def reject
    @recommendation = Recommendation.find(params[:id])
    @recommendation.update!(status: 'rejected', rejection_reason: params[:rejection_reason])
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to recommendations_path, notice: "Recommendation rejected." }
    end
  end

  def hold
    @recommendation = Recommendation.find(params[:id])
    @recommendation.update!(status: 'on_hold')
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to recommendations_path, notice: "Recommendation put on hold." }
    end
  end
end
