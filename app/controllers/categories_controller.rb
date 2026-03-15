class CategoriesController < ApplicationController
  def index
    @categories = Category.active.order(:name)
    @categories = @categories.where(status: params[:status]) if params[:status].present?
  end

  def show
    @category = Category.find(params[:id])
    @snapshots = @category.category_snapshots.recent.limit(30)
    @recommendations = @category.recommendations.order(created_at: :desc).limit(10)
    @products_count = @category.products.count
  end

  def edit
    @category = Category.find(params[:id])
  end

  def update
    @category = Category.find(params[:id])
    if @category.update(category_params)
      redirect_to @category, notice: "Category updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def category_params
    params.require(:category).permit(:margin_rate, :amazon_node_id)
  end
end
