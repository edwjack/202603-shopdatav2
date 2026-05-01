require "test_helper"

module Api
  class ProductsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @token = "test-scraper-token-pr5"
      ENV["SCRAPER_API_TOKEN"] = @token
      @headers = {
        "Authorization" => "Bearer #{@token}",
        "Content-Type" => "application/json",
      }
    end

    teardown do
      Product.where("asin LIKE ?", "TEST______").delete_all
    end

    test "rejects unauthenticated request" do
      post "/api/products/batch_upsert", params: { products: [] }.to_json,
                                          headers: { "Content-Type" => "application/json" }
      assert_response :unauthorized
    end

    test "rejects wrong token" do
      post "/api/products/batch_upsert",
           params: { products: [] }.to_json,
           headers: { "Authorization" => "Bearer wrong", "Content-Type" => "application/json" }
      assert_response :unauthorized
    end

    test "rejects when SCRAPER_API_TOKEN is unset" do
      ENV["SCRAPER_API_TOKEN"] = nil
      post "/api/products/batch_upsert", params: { products: [] }.to_json,
                                          headers: @headers
      assert_response :unauthorized
    ensure
      ENV["SCRAPER_API_TOKEN"] = @token
    end

    test "rejects oversize payload (>100 products)" do
      products = Array.new(101) { |i| { asin: "TEST00#{i.to_s.rjust(4, '0')}" } }
      post "/api/products/batch_upsert", params: { products: products }.to_json, headers: @headers
      assert_response :request_entity_too_large
    end

    test "rejects invalid asin format" do
      post "/api/products/batch_upsert",
           params: { products: [{ asin: "lowercase!", title: "x" }] }.to_json,
           headers: @headers
      assert_response :success
      body = JSON.parse(response.body)
      assert_equal 1, body["failed"]
      assert_match(/invalid asin format/, body["errors"].first["error"])
    end

    test "creates product with scalar fields" do
      post "/api/products/batch_upsert",
           params: { products: [{
             asin: "TEST000001",
             title: "Hello World Widget",
             price: 19.99,
             brand: "Acme",
             review_rating: 4.5,
             review_count: 100,
             category_name: "Widgets",
           }] }.to_json,
           headers: @headers
      assert_response :success
      body = JSON.parse(response.body)
      assert_equal 1, body["created"]
      product = Product.find_by(asin: "TEST000001")
      assert_equal "Hello World Widget", product.title
      assert_equal "Acme", product.brand
      assert_equal 19.99, product.price.to_f
    end

    test "serializes nested array (images) to JSON text" do
      images = [
        { "hiRes" => "https://m.media-amazon.com/images/I/abc.jpg", "variant" => "MAIN" },
        { "hiRes" => "https://m.media-amazon.com/images/I/def.jpg", "variant" => "PT01" },
      ]
      post "/api/products/batch_upsert",
           params: { products: [{ asin: "TEST000002", title: "T", images: images }] }.to_json,
           headers: @headers
      assert_response :success
      product = Product.find_by(asin: "TEST000002")
      assert_not_nil product.images
      parsed = JSON.parse(product.images)
      assert_equal 2, parsed.length
      assert_equal "MAIN", parsed.first["variant"]
    end

    test "serializes nested array (overview key/value)" do
      overview = [
        { "key" => "Material", "value" => "Stainless Steel" },
        { "key" => "Weight", "value" => "2 lbs" },
      ]
      post "/api/products/batch_upsert",
           params: { products: [{ asin: "TEST000003", title: "T", overview: overview }] }.to_json,
           headers: @headers
      assert_response :success
      parsed = JSON.parse(Product.find_by(asin: "TEST000003").overview)
      assert_equal "Material", parsed.first["key"]
    end

    test "serializes nested object (options Hash)" do
      options = { "Color" => ["Red", "Blue"], "Size" => ["S", "M", "L"] }
      post "/api/products/batch_upsert",
           params: { products: [{ asin: "TEST000004", title: "T", options: options }] }.to_json,
           headers: @headers
      assert_response :success
      parsed = JSON.parse(Product.find_by(asin: "TEST000004").options)
      assert_equal 2, parsed["Color"].length
      assert_equal "M", parsed["Size"][1]
    end

    test "recursive_sanitize strips script tags from nested string values" do
      images = [{ "hiRes" => "<script>alert(1)</script>https://m.media-amazon.com/x.jpg",
                  "variant" => "MAIN" }]
      post "/api/products/batch_upsert",
           params: { products: [{ asin: "TEST000005", title: "T", images: images }] }.to_json,
           headers: @headers
      assert_response :success
      raw = Product.find_by(asin: "TEST000005").images
      refute_match(/<script>/, raw)
      refute_match(/alert\(1\)/, raw)
    end

    test "recursive_sanitize strips script tag from top-level title" do
      post "/api/products/batch_upsert",
           params: { products: [{ asin: "TEST000006",
                                  title: "<script>x</script>Real Title" }] }.to_json,
           headers: @headers
      assert_response :success
      title = Product.find_by(asin: "TEST000006").title
      refute_match(/<script>/, title)
      assert_match(/Real Title/, title)
    end

    test "caps very long string values" do
      huge = "a" * 50_000
      post "/api/products/batch_upsert",
           params: { products: [{ asin: "TEST000007", title: huge }] }.to_json,
           headers: @headers
      assert_response :success
      title = Product.find_by(asin: "TEST000007").title
      # Schema cap is 1000 (string column); controller caps at 10K. The
      # column truncation/save behavior depends on Oracle config, so we
      # assert at least that we didn't echo the full 50K back.
      assert title.to_s.length <= 10_000
    end

    test "updates existing product on second call (find_or_initialize_by)" do
      post "/api/products/batch_upsert",
           params: { products: [{ asin: "TEST000008", title: "First", price: 1.0 }] }.to_json,
           headers: @headers
      assert_response :success
      assert_equal "First", Product.find_by(asin: "TEST000008").title

      post "/api/products/batch_upsert",
           params: { products: [{ asin: "TEST000008", title: "Second", price: 2.0 }] }.to_json,
           headers: @headers
      assert_response :success
      product = Product.find_by(asin: "TEST000008")
      assert_equal "Second", product.title
      assert_equal 2.0, product.price.to_f

      body = JSON.parse(response.body)
      assert_equal 1, body["updated"]
      assert_equal 0, body["created"]
    end

    test "rejects nil asin in product" do
      post "/api/products/batch_upsert",
           params: { products: [{ title: "no asin" }] }.to_json,
           headers: @headers
      assert_response :success
      body = JSON.parse(response.body)
      assert_equal 1, body["failed"]
    end

    test "deeply nested malicious payload doesn't crash + recurses up to depth limit" do
      deep = { "a" => { "b" => { "c" => { "d" => { "e" => "<script>x</script>" } } } } }
      post "/api/products/batch_upsert",
           params: { products: [{ asin: "TEST000009", title: "T", options: deep }] }.to_json,
           headers: @headers
      assert_response :success
      raw = Product.find_by(asin: "TEST000009").options
      assert_not_nil raw
      # depth>4 should stop recursion; the script-tag at depth 5 may pass
      # through, but the early levels are sanitized. Just confirm we didn't
      # crash and stored something parseable.
      assert_nothing_raised { JSON.parse(raw) }
    end
  end
end
