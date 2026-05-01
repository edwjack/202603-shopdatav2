module Api
  class ProductsController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_scraper_token

    MAX_PRODUCTS_PER_REQUEST = 100
    MAX_NESTED_DEPTH = 4
    MAX_STRING_LENGTH = 10_000
    MAX_ARRAY_LENGTH = 200
    ASIN_REGEX = /\A[A-Z0-9]{10}\z/

    SCALAR_FIELDS = %i[asin title price brand review_rating review_count
                       category_name quantity].freeze
    # Nested fields the scraper may send. The Product schema stores them as
    # serialized JSON text columns, so the controller is responsible for
    # JSON.dump before save.
    NESTED_ARRAY_FIELDS = %i[about_this tags].freeze       # array of strings/objects
    NESTED_OBJECT_FIELDS = %i[images overview options].freeze  # array-of-hash or hash

    def batch_upsert
      products_params = params.require(:products)
      unless products_params.is_a?(Array) || products_params.is_a?(ActionController::Parameters)
        return render json: { error: "products must be an array" }, status: :bad_request
      end
      products_array = products_params.to_a
      if products_array.size > MAX_PRODUCTS_PER_REQUEST
        return head :request_entity_too_large
      end

      created = updated = failed = 0
      errors = []

      products_array.each do |product_data|
        begin
          attrs = permitted_product_params(product_data)
          asin = attrs[:asin]
          unless asin.is_a?(String) && asin.match?(ASIN_REGEX)
            failed += 1
            errors << { asin: asin, error: "invalid asin format" }
            next
          end

          product = Product.find_or_initialize_by(asin: asin)
          was_new = product.new_record?
          product.assign_attributes(attrs)
          product.save!
          was_new ? created += 1 : updated += 1
        rescue => e
          failed += 1
          errors << { asin: product_data[:asin], error: e.message }
        end
      end

      render json: { created: created, updated: updated, failed: failed, errors: errors }
    end

    private

    def authenticate_scraper_token
      expected = ENV["SCRAPER_API_TOKEN"]
      head(:unauthorized) and return if expected.blank?
      token = request.headers["Authorization"]&.delete_prefix("Bearer ")
      head(:unauthorized) and return unless token.present? && ActiveSupport::SecurityUtils.secure_compare(token, expected)
    end

    # Builds a sanitized + serialized attribute hash for Product.assign_attributes.
    # H3/F10/Q5 fix: nested Hash/Array values are recursed and sanitized at every
    # level, then the JSON-text columns (images/overview/options/about_this/tags)
    # are JSON.dumped so the assignment matches the column type.
    def permitted_product_params(data)
      hash = data.is_a?(ActionController::Parameters) ? data.to_unsafe_h : data.to_h
      hash = hash.with_indifferent_access
      out = {}

      SCALAR_FIELDS.each do |key|
        next unless hash.key?(key)
        val = hash[key]
        out[key] = val.is_a?(String) ? recursive_sanitize(val) : val
      end

      (NESTED_ARRAY_FIELDS + NESTED_OBJECT_FIELDS).each do |key|
        next unless hash.key?(key)
        nested = recursive_sanitize(hash[key])
        # Product columns are TEXT — serialize. nil stays nil so the column
        # can be cleared explicitly.
        out[key] = nested.nil? ? nil : nested.to_json
      end

      out
    end

    # Recursively sanitize a value tree:
    # - String: ActionController::Base.helpers.sanitize, length-capped
    # - Hash: sanitize values, sanitize string keys
    # - Array: sanitize each element (length capped to prevent unbounded blow-up)
    # - depth limit so a malicious payload can't recurse forever
    def recursive_sanitize(obj, depth: 0)
      return nil if obj.nil?
      return obj if depth > MAX_NESTED_DEPTH
      case obj
      when String
        sanitized = ActionController::Base.helpers.sanitize(obj)
        sanitized = sanitized.to_s
        sanitized.length > MAX_STRING_LENGTH ? sanitized[0, MAX_STRING_LENGTH] : sanitized
      when Hash, ActionController::Parameters
        h = obj.is_a?(ActionController::Parameters) ? obj.to_unsafe_h : obj
        h.each_with_object({}) do |(k, v), acc|
          key = k.is_a?(String) ? recursive_sanitize(k, depth: depth + 1) : k
          acc[key] = recursive_sanitize(v, depth: depth + 1)
        end
      when Array
        capped = obj.first(MAX_ARRAY_LENGTH)
        capped.map { |v| recursive_sanitize(v, depth: depth + 1) }
      when Numeric, TrueClass, FalseClass
        obj
      else
        obj.to_s
      end
    end
  end
end
