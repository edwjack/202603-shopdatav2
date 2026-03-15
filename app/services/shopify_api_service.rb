class ShopifyApiService
  API_VERSION = "2025-01"

  def initialize
    @shop_domain = ENV['SHOPIFY_SHOP_DOMAIN']
    @access_token = ENV['SHOPIFY_ACCESS_TOKEN']
  end

  def create_product(product)
    query = <<~GRAPHQL
      mutation productCreate($input: ProductInput!, $media: [CreateMediaInput!]) {
        productCreate(input: $input, media: $media) {
          product {
            id
            title
            variants(first: 1) {
              edges {
                node {
                  id
                  price
                }
              }
            }
          }
          userErrors {
            field
            message
          }
        }
      }
    GRAPHQL

    images = product.images_data
    media = images.first(10).map do |img|
      url = img.is_a?(Hash) ? (img['hiRes'] || img['large'] || img['url'] || img['src']) : img
      { originalSource: url, mediaContentType: "IMAGE" } if url.present?
    end.compact

    variables = {
      input: {
        title: product.title,
        bodyHtml: build_description(product),
        vendor: product.brand || "Unknown",
        productType: product.category&.name || "General",
        tags: product.tags_data,
        status: "DRAFT"
      },
      media: media
    }

    result = graphql_request(query, variables)
    data = result.dig('data', 'productCreate')
    errors = data&.dig('userErrors')

    if errors.present? && errors.any?
      raise "Shopify create failed: #{errors.map { |e| e['message'] }.join(', ')}"
    end

    data['product']
  end

  def update_product(product)
    query = <<~GRAPHQL
      mutation productUpdate($input: ProductInput!) {
        productUpdate(input: $input) {
          product {
            id
            title
          }
          userErrors {
            field
            message
          }
        }
      }
    GRAPHQL

    variables = {
      input: {
        id: "gid://shopify/Product/#{product.shopify_product_id}",
        title: product.title,
        bodyHtml: build_description(product),
        vendor: product.brand || "Unknown"
      }
    }

    result = graphql_request(query, variables)
    data = result.dig('data', 'productUpdate')
    errors = data&.dig('userErrors')

    if errors.present? && errors.any?
      raise "Shopify update failed: #{errors.map { |e| e['message'] }.join(', ')}"
    end

    data['product']
  end

  def publish_product(shopify_gid)
    # First get the publication ID for the online store
    pub_query = <<~GRAPHQL
      query {
        publications(first: 10) {
          edges {
            node {
              id
              name
            }
          }
        }
      }
    GRAPHQL

    pub_result = graphql_request(pub_query)
    publications = pub_result.dig('data', 'publications', 'edges') || []
    online_store = publications.find { |p| p.dig('node', 'name')&.include?('Online Store') }
    publication_id = online_store&.dig('node', 'id')

    return unless publication_id

    query = <<~GRAPHQL
      mutation publishablePublish($id: ID!, $input: [PublicationInput!]!) {
        publishablePublish(id: $id, input: $input) {
          publishable {
            ... on Product {
              id
            }
          }
          userErrors {
            field
            message
          }
        }
      }
    GRAPHQL

    variables = {
      id: shopify_gid,
      input: [{ publicationId: publication_id }]
    }

    result = graphql_request(query, variables)
    errors = result.dig('data', 'publishablePublish', 'userErrors')

    if errors.present? && errors.any?
      raise "Shopify publish failed: #{errors.map { |e| e['message'] }.join(', ')}"
    end

    result.dig('data', 'publishablePublish', 'publishable')
  end

  def update_variant_price(variant_gid, price)
    query = <<~GRAPHQL
      mutation productVariantUpdate($input: ProductVariantInput!) {
        productVariantUpdate(input: $input) {
          productVariant {
            id
            price
          }
          userErrors {
            field
            message
          }
        }
      }
    GRAPHQL

    variables = {
      input: {
        id: variant_gid,
        price: price.to_s
      }
    }

    result = graphql_request(query, variables)
    errors = result.dig('data', 'productVariantUpdate', 'userErrors')

    if errors.present? && errors.any?
      raise "Shopify variant update failed: #{errors.map { |e| e['message'] }.join(', ')}"
    end

    result.dig('data', 'productVariantUpdate', 'productVariant')
  end

  def get_product(shopify_gid)
    query = <<~GRAPHQL
      query product($id: ID!) {
        product(id: $id) {
          id
          title
          status
          variants(first: 1) {
            edges {
              node {
                id
                price
              }
            }
          }
        }
      }
    GRAPHQL

    result = graphql_request(query, { id: shopify_gid })
    result.dig('data', 'product')
  end

  private

  def build_description(product)
    parts = []
    about = product.about_this_data
    parts << "<ul>#{about.map { |item| "<li>#{ERB::Util.html_escape(item)}</li>" }.join}</ul>" if about.any?

    overview = product.overview_data
    if overview.any?
      rows = overview.map do |attr|
        key = attr.is_a?(Hash) ? (attr['name'] || attr['key']) : attr.to_s
        val = attr.is_a?(Hash) ? attr['value'] : ''
        "<tr><td><strong>#{ERB::Util.html_escape(key)}</strong></td><td>#{ERB::Util.html_escape(val)}</td></tr>"
      end
      parts << "<table>#{rows.join}</table>"
    end

    parts.join("\n")
  end

  def graphql_request(query, variables = {})
    uri = URI("https://#{@shop_domain}/admin/api/#{API_VERSION}/graphql.json")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.path)
    request['Content-Type'] = 'application/json'
    request['X-Shopify-Access-Token'] = @access_token
    request.body = { query: query, variables: variables }.to_json

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      raise "Shopify API error (#{response.code}): #{response.body.truncate(500)}"
    end

    JSON.parse(response.body)
  end
end
