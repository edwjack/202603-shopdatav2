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
      # params[:products] (not require!) so a missing key returns the same
      # JSON error envelope as a malformed array, instead of Rails' default
      # ParameterMissing 400 (Gate v2 fix).
      products_params = params[:products]
      if products_params.nil?
        return render json: { error: "products is required" }, status: :bad_request
      end
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
        raw = hash[key]
        # Backcompat (Gate v2 GAP1): if the caller already serialized to a
        # JSON-string, parse first so we don't double-encode (avoid storing
        # `"[\"...\"]"` instead of `["..."]`). On parse failure, treat as
        # an opaque string — sanitize and store raw.
        if raw.is_a?(String)
          parsed = begin
                     JSON.parse(raw)
                   rescue JSON::ParserError
                     :__not_json__
                   end
          if parsed == :__not_json__
            out[key] = recursive_sanitize(raw)
            next
          end
          raw = parsed
        end
        nested = recursive_sanitize(raw)
        # Product columns are TEXT — serialize. nil stays nil so the column
        # can be cleared explicitly.
        out[key] = nested.nil? ? nil : nested.to_json
      end

      out
    end

    # Recursively sanitize a value tree:
    # - String: always sanitize + length-cap, even at max depth (Gate v2 GAP2)
    # - Hash / Array: stop descending past MAX_NESTED_DEPTH and replace the
    #   subtree with `nil` so deep raw HTML can't be stored unsanitized
    # - Numeric/Bool: pass through
    def recursive_sanitize(obj, depth: 0)
      return nil if obj.nil?
      case obj
      when String
        # Sanitize at every depth — string content must never be raw HTML
        # in storage, regardless of nesting level.
        sanitized = ActionController::Base.helpers.sanitize(obj).to_s
        if sanitized.length > MAX_STRING_LENGTH
          # R-NEW-10 visibility: a legitimate large payload (rare, since
          # Amazon titles ≤ 200 chars) being silently truncated needs to
          # surface in logs so ops can spot it.
          Rails.logger.warn(
            "[batch_upsert] truncated string from #{sanitized.length} to #{MAX_STRING_LENGTH}"
          )
          sanitized[0, MAX_STRING_LENGTH]
        else
          sanitized
        end
      when Numeric, TrueClass, FalseClass
        obj
      when Hash, ActionController::Parameters
        if depth > MAX_NESTED_DEPTH
          Rails.logger.warn("[batch_upsert] dropped Hash at depth=#{depth} (> MAX_NESTED_DEPTH=#{MAX_NESTED_DEPTH})")
          return nil
        end
        h = obj.is_a?(ActionController::Parameters) ? obj.to_unsafe_h : obj
        h.each_with_object({}) do |(k, v), acc|
          key = k.is_a?(String) ? recursive_sanitize(k, depth: depth + 1) : k
          acc[key] = recursive_sanitize(v, depth: depth + 1)
        end
      when Array
        if depth > MAX_NESTED_DEPTH
          Rails.logger.warn("[batch_upsert] dropped Array at depth=#{depth} (> MAX_NESTED_DEPTH=#{MAX_NESTED_DEPTH})")
          return nil
        end
        if obj.length > MAX_ARRAY_LENGTH
          Rails.logger.warn("[batch_upsert] truncated Array from #{obj.length} to #{MAX_ARRAY_LENGTH}")
        end
        capped = obj.first(MAX_ARRAY_LENGTH)
        capped.map { |v| recursive_sanitize(v, depth: depth + 1) }
      else
        # Unknown type — coerce to string and sanitize so nothing slips through.
        sanitized = ActionController::Base.helpers.sanitize(obj.to_s).to_s
        sanitized.length > MAX_STRING_LENGTH ? sanitized[0, MAX_STRING_LENGTH] : sanitized
      end
    end
  end
end
