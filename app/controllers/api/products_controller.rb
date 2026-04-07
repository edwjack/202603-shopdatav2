module Api
  class ProductsController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_scraper_token

    def batch_upsert
      products_params = params.require(:products)
      return head :request_entity_too_large if products_params.size > 100

      created = updated = failed = 0
      errors = []

      products_params.each do |product_data|
        begin
          product = Product.find_or_initialize_by(asin: product_data[:asin])
          was_new = product.new_record?
          product.assign_attributes(permitted_product_params(product_data))
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

    def permitted_product_params(data)
      data.permit(:asin, :title, :price, :brand, :review_rating, :review_count,
                   :about_this, :tags, :category_name, :images, :overview, :options, :quantity)
                   .transform_values { |v| v.is_a?(String) ? ActionController::Base.helpers.sanitize(v) : v }
    end
  end
end
