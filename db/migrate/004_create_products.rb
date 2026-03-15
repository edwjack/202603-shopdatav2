class CreateProducts < ActiveRecord::Migration[8.0]
  def up
    create_table :products do |t|
      t.string :asin, limit: 20, null: false
      t.references :category, foreign_key: true
      t.string :title, limit: 1000
      t.string :brand, limit: 200
      t.decimal :price, precision: 10, scale: 2
      t.text :about_this
      t.string :category_name, limit: 200
      t.text :tags
      t.text :images
      t.text :overview
      t.text :options
      t.integer :quantity
      t.decimal :review_rating, precision: 3, scale: 2
      t.integer :review_count
      t.string :sourcing_status, limit: 20, default: 'pending'
      t.string :scraper_status, limit: 20
      t.timestamp :scraping_synced_at
      t.integer :shopify_product_id
      t.string :shopify_status, limit: 20
      t.decimal :shopify_price, precision: 10, scale: 2
      t.timestamp :shopify_synced_at
      t.timestamps
    end
    add_index :products, :asin, unique: true
    add_index :products, :category_id
    add_index :products, :sourcing_status
    add_index :products, :scraper_status
    add_index :products, :shopify_status

    execute "ALTER TABLE products ADD title_vector VECTOR(384, FLOAT32)"
  end

  def down
    drop_table :products
  end
end
