class AddMarginRateToCategories < ActiveRecord::Migration[8.0]
  def change
    add_column :categories, :margin_rate, :decimal, precision: 5, scale: 2, default: 50.0
  end
end
