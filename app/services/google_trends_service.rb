class GoogleTrendsService
  def self.fetch(category)
    if MockDataService.mock_mode?
      data = MockDataService.load('google_trends_sample')
      category_data = data['categories'][category.slug] || data['categories'].values.first
      {
        trends_interest: category_data['interest_over_time'],
        trends_cv:       category_data['cv'],
        trends_yoy:      category_data['yoy_change']
      }
    else
      fetch_real(category)
    end
  end

  private

  def self.fetch_real(category)
    keywords = [category.name]
    response = ScraperClientService.collect_sync('/collect/trends', { keywords: keywords }, timeout: 120)

    return {} if response['error']

    trends = response['trends'] || []
    return {} if trends.empty?

    # Aggregate across keywords: use first keyword as primary signal
    primary = trends.first
    {
      trends_interest: primary['interest'],
      trends_cv:       primary['cv'],
      trends_yoy:      primary['yoy_change']&.to_s
    }
  rescue => e
    Rails.logger.error "[GoogleTrendsService] fetch_real failed: #{e.message}"
    {}
  end
end
