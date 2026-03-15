class SocialSignalService
  def self.fetch(category)
    if MockDataService.mock_mode?
      data = MockDataService.load('social_signal_sample')
      category_data = data['categories'][category.slug] || data['categories'].values.first
      {
        reddit_mentions:  category_data['reddit_mentions'],
        reddit_sentiment: category_data['reddit_sentiment'],
        tiktok_views:     category_data['tiktok_views']
      }
    else
      fetch_real(category)
    end
  end

  private

  def self.fetch_real(category)
    keywords = [category.name]
    response = ScraperClientService.collect_sync('/collect/social', { keywords: keywords, subreddits: [] }, timeout: 60)

    return {} if response['error']

    reddit = response['reddit'] || {}
    {
      reddit_mentions:  reddit['mentions'],
      reddit_sentiment: reddit['sentiment'],
      tiktok_views:     response['tiktok_views']
    }
  rescue => e
    Rails.logger.error "[SocialSignalService] fetch_real failed: #{e.message}"
    {}
  end
end
