class ShopifyPublishJob < ApplicationJob
  queue_as :default

  def perform(product_id)
    product = Product.find(product_id)

    # Guard: skip if already publishing
    if product.shopify_status == 'publishing'
      Rails.logger.warn "[ShopifyPublishJob] Product #{product.asin} already publishing, skipping"
      return
    end

    ShopifyPublishService.publish_single(product)
  end
end
