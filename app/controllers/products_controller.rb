class ProductsController < ApplicationController
  def index
    scope = Product.order(created_at: :desc)
    scope = scope.where(category_id: params[:category_id]) if params[:category_id].present?
    scope = scope.where(sourcing_status: params[:status]) if params[:status].present?
    scope = scope.where(shopify_status: params[:shopify_status]) if params[:shopify_status].present?
    if params[:q].present?
      scope = scope.where("LOWER(title) LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].downcase)}%")
    end
    @products, @page, @has_next, @total, @total_pages = paginate(scope)
  end

  def show
    @product = Product.find(params[:id])
  end

  def publish_shopify
    @product = Product.find(params[:id])

    unless @product.sourcing_status == 'approved' && @product.scraper_status == 'completed'
      redirect_to @product, alert: "Product must be approved and scraped before publishing."
      return
    end

    if @product.shopify_status == 'publishing'
      redirect_to @product, alert: "Product is already being published."
      return
    end

    ShopifyPublishJob.perform_later(@product.id)
    redirect_to @product, notice: "Publishing to Shopify queued."
  end

  def batch_publish_shopify
    product_ids = params[:product_ids]
    if product_ids.blank?
      redirect_to products_path, alert: "No products selected."
      return
    end

    products = Product.where(id: product_ids, sourcing_status: 'approved', scraper_status: 'completed')
                      .where.not(shopify_status: 'publishing')
    count = 0
    products.each do |product|
      ShopifyPublishJob.perform_later(product.id)
      count += 1
    end

    redirect_to products_path, notice: "#{count} products queued for Shopify publishing."
  end
end
