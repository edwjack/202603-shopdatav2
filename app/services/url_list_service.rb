class UrlListService
  def self.collect(category)
    if MockDataService.mock_mode?
      collect_mock(category)
    else
      collect_real(category)
    end
  end

  private

  def self.collect_mock(category)
    data = MockDataService.load('url_list_sample')
    # Filter by category slug
    category_asins = data.select { |item| item['category_slug'] == category.slug }
    # If no exact match, use all (for testing with any category)
    category_asins = data if category_asins.empty?

    count = 0
    category_asins.each do |item|
      unless AsinUrl.exists?(category_id: category.id, asin: item['asin'])
        AsinUrl.create!(
          category: category,
          asin: item['asin'],
          source: item['source'] || 'best_sellers',
          status: 'pending',
          collected_at: Time.current
        )
        count += 1
      end
    end

    { processed_count: count, asin_count: count }
  end

  def self.collect_real(category)
    return { processed_count: 0, asin_count: 0 } unless category.amazon_node_id.present?

    response = ScraperClientService.collect_async('/collect/urls', {
      amazon_node_id: category.amazon_node_id,
      pages: 1
    })
    return { processed_count: 0, asin_count: 0 } if response['error']

    results = response['results'] || []
    count = 0
    results.each do |item|
      next unless item['asin'].present?
      unless AsinUrl.exists?(category_id: category.id, asin: item['asin'])
        AsinUrl.create!(
          category: category,
          asin: item['asin'],
          source: item['source'] || 'best_sellers',
          status: 'pending',
          collected_at: Time.current
        )
        count += 1
      end
    end

    { processed_count: count, asin_count: results.size }
  end
end
