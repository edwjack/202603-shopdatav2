class MoversShakersService
  def self.fetch(category)
    if MockDataService.mock_mode?
      data = MockDataService.load('movers_shakers_sample')
      category_data = data['categories'][category.slug] || data['categories'].values.first
      {
        movers_data: category_data
      }
    else
      return {} unless category.amazon_node_id.present?

      response = ScraperClientService.collect_sync('/collect/movers', {
        amazon_node_id: category.amazon_node_id,
        category_slug: category.slug
      })
      return {} if response['error']

      { movers_data: response['movers'] || [] }
    end
  end
end
