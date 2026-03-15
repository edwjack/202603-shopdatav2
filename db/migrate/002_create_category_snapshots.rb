class CreateCategorySnapshots < ActiveRecord::Migration[8.0]
  def change
    create_table :category_snapshots do |t|
      t.references :category, null: false, foreign_key: true
      t.date :snapshot_date, null: false
      t.integer :avg_bsr
      t.decimal :bsr_7d_change, precision: 5, scale: 2
      t.decimal :bsr_30d_change, precision: 5, scale: 2
      t.integer :new_entries
      t.integer :total_products
      t.decimal :avg_price, precision: 10, scale: 2
      t.decimal :price_in_range_pct, precision: 5, scale: 2
      t.integer :avg_reviews
      t.decimal :avg_rating, precision: 3, scale: 2
      t.decimal :fba_ratio, precision: 3, scale: 2
      t.integer :trends_interest
      t.decimal :trends_cv, precision: 5, scale: 4
      t.string :trends_yoy, limit: 20
      t.integer :reddit_mentions
      t.decimal :reddit_sentiment, precision: 3, scale: 2
      t.string :tiktok_views, limit: 50
      t.text :movers_data
      t.text :competitor_data
      t.text :raw_data
      t.timestamps
    end
    add_index :category_snapshots, [:category_id, :snapshot_date], unique: true
  end
end
