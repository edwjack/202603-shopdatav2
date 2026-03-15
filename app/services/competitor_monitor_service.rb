require 'net/http'

class CompetitorMonitorService
  def self.fetch(store)
    if MockDataService.mock_mode?
      data = MockDataService.load('competitor_stores_sample')
      store_data = data['stores'][store.name.downcase.gsub(/\s+/, '-')] || data['stores'].values.first
      {
        competitor_data: store_data
      }
    else
      uri = URI("#{store.url}/products.json?limit=250")
      response = Net::HTTP.get_response(uri)
      if response.is_a?(Net::HTTPSuccess)
        products = JSON.parse(response.body)['products'] || []
        {
          competitor_data: {
            total_products: products.size,
            fetched_at: Time.current.iso8601
          }
        }
      else
        { competitor_data: { error: "HTTP #{response.code}", fetched_at: Time.current.iso8601 } }
      end
    end
  end
end
