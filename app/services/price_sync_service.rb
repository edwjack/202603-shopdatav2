class PriceSyncService
  def self.sync(mode: :price)
    if MockDataService.mock_mode?
      sync_mock(mode)
    else
      sync_real(mode)
    end
  end

  private

  def self.sync_real(mode)
    products = Product.needs_price_sync
    asins = products.pluck(:asin)
    return { processed_count: 0, synced: 0, changes: 0 } if asins.empty?

    response = ScraperClientService.collect_async('/resync/price', { asins: asins })
    return { processed_count: 0, synced: 0, changes: 0 } if response['error']

    results = response['results'] || []
    synced = 0
    changes = 0

    results.each do |item|
      next unless item['success'] && item['asin'].present?
      product = Product.find_by(asin: item['asin'])
      next unless product

      attrs = { data_synced_at: Time.current }
      changed = false

      if (mode == :price || mode == :title) && item['price'].to_f > 0
        if product.price != item['price'].to_d
          attrs[:price] = item['price']
          changed = true
        end
      end

      product.update!(attrs)
      synced += 1
      changes += 1 if changed
    rescue => e
      Rails.logger.error "[PriceSyncService] Failed to update #{item['asin']}: #{e.message}"
    end

    { processed_count: synced, synced: synced, changes: changes }
  rescue => e
    Rails.logger.error "[PriceSyncService] sync_real failed: #{e.message}"
    { processed_count: 0, synced: 0, changes: 0 }
  end

  def self.sync_mock(mode)
    data = MockDataService.load('price_sync_sample')
    synced = 0
    changes = 0

    data.each do |item|
      product = Product.find_by(asin: item['asin'])
      next unless product

      attrs = { data_synced_at: Time.current }
      changed = false

      if mode == :price || mode == :title
        if item['price'] && product.price != item['price'].to_d
          attrs[:price] = item['price']
          changed = true
        end
      end

      if mode == :title
        if item['title'] && product.title != item['title']
          attrs[:title] = item['title']
          changed = true
        end
      end

      product.update!(attrs)
      synced += 1
      changes += 1 if changed
    end

    { processed_count: synced, synced: synced, changes: changes }
  end
end
