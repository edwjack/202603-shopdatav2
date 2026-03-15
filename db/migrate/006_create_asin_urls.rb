class CreateAsinUrls < ActiveRecord::Migration[8.0]
  def change
    create_table :asin_urls do |t|
      t.references :category, null: false, foreign_key: true
      t.string :asin, limit: 20, null: false
      t.string :source, limit: 50
      t.timestamp :collected_at
      t.string :status, limit: 20, default: 'pending'
      t.timestamps
    end
    add_index :asin_urls, [:category_id, :asin], unique: true
    add_index :asin_urls, :status
  end
end
