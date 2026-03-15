class ShopifyPriceSyncService
  def self.sync
    new.sync
  end

  def sync
    products = Product.published_shopify.where.not(shopify_product_id: nil)
    updated = 0
    failed = 0

    products.find_each do |product|
      margin = product.category&.margin_rate || 50.0
      new_shopify_price = (product.price * (1 + margin / 100)).round(2)

      next if product.shopify_price == new_shopify_price

      if MockDataService.mock_mode?
        product.update!(shopify_price: new_shopify_price, shopify_synced_at: Time.current)
        Rails.logger.info "[ShopifyPriceSyncService] [MOCK] Updated #{product.asin} price to $#{new_shopify_price}"
        updated += 1
        next
      end

      begin
        shopify_gid = "gid://shopify/Product/#{product.shopify_product_id}"
        shopify_product = api.get_product(shopify_gid)

        if shopify_product.nil?
          product.update!(shopify_status: 'failed', shopify_error: 'Deleted from Shopify')
          failed += 1
          next
        end

        variant_gid = shopify_product.dig('variants', 'edges', 0, 'node', 'id')
        if variant_gid
          api.update_variant_price(variant_gid, new_shopify_price)
          product.update!(shopify_price: new_shopify_price, shopify_synced_at: Time.current, shopify_error: nil)
          updated += 1
        end

        sleep 0.5 # Rate limit
      rescue => e
        product.update!(shopify_error: e.message.truncate(2000))
        Rails.logger.error "[ShopifyPriceSyncService] Failed to sync #{product.asin}: #{e.message}"
        failed += 1
      end
    end

    Rails.logger.info "[ShopifyPriceSyncService] Synced #{updated} prices (#{failed} failed)"
    { processed_count: updated + failed, updated: updated, failed: failed }
  end

  private

  def api
    @api ||= ShopifyApiService.new
  end
end
