class CreateCategories < ActiveRecord::Migration[8.0]
  def change
    create_table :categories do |t|
      t.string :name, limit: 200, null: false
      t.string :slug, limit: 200, null: false
      t.string :amazon_node_id, limit: 50
      t.string :description, limit: 2000
      t.string :target_audience, limit: 500
      t.string :risk_level, limit: 20, default: 'low'
      t.text :example_products  # JSON stored as CLOB
      t.string :status, limit: 20, default: 'tracking'
      t.boolean :active, default: true
      t.timestamps
    end
    add_index :categories, :slug, unique: true
    add_index :categories, :status
  end
end
