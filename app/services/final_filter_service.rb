class FinalFilterService
  def self.filter(category)
    products = Product.where(category: category, sourcing_status: 'approved', scraper_status: 'completed')
    total = products.count
    reasons = { quantity: 0, images: 0, features: 0 }
    rejected = 0

    products.find_each do |product|
      reason = check_filters(product)
      if reason
        product.update!(sourcing_status: 'rejected')
        reasons[reason] += 1
        rejected += 1
      end
      # If no reason, keep as 'approved'
    end

    passed = total - rejected
    { processed_count: passed, total: total, passed: passed, rejected: rejected, reasons: reasons }
  end

  private

  def self.check_filters(product)
    # 1. Quantity < 3: reject (stock risk)
    return :quantity if product.quantity.nil? || product.quantity < 3

    # 2. No images (uses CLOB helper — handles "[]" string)
    return :images if product.images_data.empty?

    # 3. No features/about_this (uses CLOB helper — handles "[]" string)
    return :features if product.about_this_data.empty?

    nil
  end
end
