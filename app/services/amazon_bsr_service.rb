class AmazonBsrService
  def self.fetch(category)
    if MockDataService.mock_mode?
      data = MockDataService.load('amazon_bsr_sample')
      category_data = data['categories'][category.slug] || data['categories'].values.first
      {
        avg_bsr:           category_data['avg_bsr'],
        bsr_7d_change:     category_data['bsr_7d_change'],
        bsr_30d_change:    category_data['bsr_30d_change'],
        new_entries:       category_data['new_entries'],
        total_products:    category_data['total_products'],
        avg_price:         category_data['avg_price'],
        price_in_range_pct: category_data['price_in_range_pct'],
        avg_reviews:       category_data['avg_reviews'],
        avg_rating:        category_data['avg_rating'],
        fba_ratio:         category_data['fba_ratio'],
        raw_data:          category_data
      }
    else
      return {} unless category.amazon_node_id.present?

      response = ScraperClientService.collect_sync('/collect/bsr', {
        amazon_node_id: category.amazon_node_id,
        category_slug: category.slug
      })
      return {} if response['error']

      products = response['products'] || []
      stats = response['stats'] || {}
      current_avg_bsr = stats['avg_bsr']

      prev_7d = CategorySnapshot.where(category: category)
                  .where('snapshot_date >= ?', 7.days.ago)
                  .order(snapshot_date: :asc).first
      prev_30d = CategorySnapshot.where(category: category)
                  .where('snapshot_date >= ?', 30.days.ago)
                  .order(snapshot_date: :asc).first

      {
        avg_bsr:           current_avg_bsr,
        bsr_7d_change:     prev_7d&.avg_bsr && current_avg_bsr ? ((current_avg_bsr - prev_7d.avg_bsr) / prev_7d.avg_bsr * 100).round(1) : nil,
        bsr_30d_change:    prev_30d&.avg_bsr && current_avg_bsr ? ((current_avg_bsr - prev_30d.avg_bsr) / prev_30d.avg_bsr * 100).round(1) : nil,
        new_entries:       compute_new_entries(category, products),
        total_products:    stats['total'],
        avg_price:         stats['avg_price'],
        price_in_range_pct: stats['price_in_range_pct'],
        avg_reviews:       stats['avg_reviews'],
        avg_rating:        stats['avg_rating'],
        fba_ratio:         stats['fba_ratio'],
        raw_data:          response.to_json
      }
    end
  end

  def self.compute_new_entries(category, products)
    return 0 unless products.present?
    current_asins = products.map { |p| p['asin'] }.compact
    prev_snapshot = CategorySnapshot.where(category: category)
                      .where('snapshot_date < ?', Date.current)
                      .order(snapshot_date: :desc).first
    return current_asins.size unless prev_snapshot

    prev_raw = JSON.parse(prev_snapshot.raw_data || '{}') rescue {}
    prev_asins = (prev_raw['products'] || []).map { |p| p['asin'] }.compact
    (current_asins - prev_asins).size
  end
end
