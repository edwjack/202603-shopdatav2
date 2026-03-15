class ProductFilterService
  HAZARD_KEYWORDS = %w[fda prescription hazmat flammable weapon].freeze

  def self.filter(category)
    products = Product.where(category: category, sourcing_status: 'pending')
    total = products.count
    reasons = { price: 0, keyword: 0, brand: 0, reviews: 0, rating: 0, hazard: 0 }
    rejected = 0
    excluded = ExcludedKeyword.active.pluck(:keyword).map(&:downcase)

    products.find_each do |product|
      reason = check_filters(product, excluded)
      if reason
        product.update!(sourcing_status: 'rejected')
        reasons[reason] += 1
        rejected += 1
      else
        product.update!(sourcing_status: 'approved')
      end
    end

    passed = total - rejected
    { processed_count: passed, total: total, passed: passed, rejected: rejected, reasons: reasons }
  end

  private

  def self.check_filters(product, excluded)
    # 1. Price filter: $30-80
    return :price if product.price.nil? || product.price < 30 || product.price > 80

    # 2. Excluded keywords: check title AND category_name
    title_lower = product.title&.downcase || ''
    category_name_lower = product.category_name&.downcase || ''
    excluded.each do |kw|
      return :keyword if title_lower.include?(kw) || category_name_lower.include?(kw)
    end

    # 3. Brand gating (case-insensitive)
    return :brand if product.brand.present? && Product::GATED_BRANDS.any? { |b| b.casecmp(product.brand) == 0 }

    # 4. Reviews minimum
    return :reviews if product.review_count.nil? || product.review_count < 10

    # 5. Rating minimum
    return :rating if product.review_rating.nil? || product.review_rating < 3.5

    # 6. Hazard keywords in title or about_this
    combined_text = "#{title_lower} #{product.about_this&.downcase}"
    HAZARD_KEYWORDS.each do |hw|
      return :hazard if combined_text.include?(hw)
    end

    nil  # All filters passed
  end
end
