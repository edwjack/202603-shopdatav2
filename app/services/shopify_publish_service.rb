class ShopifyPublishService
  def self.publish_single(product)
    new.publish_single(product)
  end

  def self.publish_batch(products)
    new.publish_batch(products)
  end

  def publish_single(product)
    return { error: "Price is zero or nil" } if product.price.nil? || product.price.zero?

    if MockDataService.mock_mode?
      return publish_mock(product)
    end

    margin = product.category&.margin_rate || 50.0
    shopify_price = (product.price * (1 + margin / 100)).round(2)

    product.update!(shopify_status: 'publishing')

    if product.shopify_product_id.present?
      shopify_product = api.update_product(product)
      shopify_gid = "gid://shopify/Product/#{product.shopify_product_id}"
    else
      shopify_product = api.create_product(product)
      shopify_gid = shopify_product['id']
      product.shopify_product_id = extract_numeric_id(shopify_gid)
    end

    # Set variant price
    variant_gid = shopify_product.dig('variants', 'edges', 0, 'node', 'id')
    api.update_variant_price(variant_gid, shopify_price) if variant_gid

    # Publish to online store
    api.publish_product(shopify_gid)

    product.update!(
      shopify_status: 'published',
      shopify_price: shopify_price,
      shopify_synced_at: Time.current,
      shopify_error: nil
    )

    { success: true, shopify_product_id: product.shopify_product_id }
  rescue => e
    product.update!(shopify_status: 'failed', shopify_error: e.message.truncate(2000))
    Rails.logger.error "[ShopifyPublishService] Failed to publish #{product.asin}: #{e.message}"
    { error: e.message }
  end

  def publish_batch(products)
    results = { published: 0, failed: 0, errors: [] }
    products.each do |product|
      result = publish_single(product)
      if result[:error]
        results[:failed] += 1
        results[:errors] << { asin: product.asin, error: result[:error] }
      else
        results[:published] += 1
      end
      sleep 0.5 # Shopify rate limit
    end
    results
  end

  private

  def api
    @api ||= ShopifyApiService.new
  end

  def extract_numeric_id(gid)
    gid.to_s.split('/').last.to_i
  end

  def publish_mock(product)
    margin = product.category&.margin_rate || 50.0
    shopify_price = (product.price * (1 + margin / 100)).round(2)
    mock_id = product.shopify_product_id || (product.id.to_i * 1000 + rand(999))

    product.update!(
      shopify_product_id: mock_id,
      shopify_status: 'published',
      shopify_price: shopify_price,
      shopify_synced_at: Time.current,
      shopify_error: nil
    )

    Rails.logger.info "[ShopifyPublishService] [MOCK] Published #{product.asin} as Shopify##{mock_id} at $#{shopify_price}"
    { success: true, shopify_product_id: mock_id }
  end
end
