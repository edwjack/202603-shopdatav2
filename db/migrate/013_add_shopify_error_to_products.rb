class AddShopifyErrorToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :shopify_error, :string, limit: 2000
  end
end
