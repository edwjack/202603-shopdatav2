class CreateCompetitorStores < ActiveRecord::Migration[8.0]
  def change
    create_table :competitor_stores do |t|
      t.string :name, limit: 200, null: false
      t.string :url, limit: 500
      t.string :shopify_domain, limit: 200
      t.boolean :active, default: true
      t.timestamp :last_crawled_at
      t.timestamps
    end
  end
end
