class CreateScrapeMetrics < ActiveRecord::Migration[8.0]
  def change
    create_table :scrape_metrics do |t|
      t.string :collector_name, limit: 50, null: false
      t.references :category, foreign_key: true, null: true
      t.date :run_date, null: false
      t.integer :attempted, default: 0
      t.integer :succeeded, default: 0
      t.integer :failed, default: 0
      t.integer :partial, default: 0
      t.decimal :success_rate, precision: 5, scale: 2
      t.integer :avg_response_ms
      t.string :error_summary, limit: 2000
      t.timestamps
    end
    add_index :scrape_metrics, [:collector_name, :run_date]
    add_index :scrape_metrics, [:category_id, :run_date]
  end
end
