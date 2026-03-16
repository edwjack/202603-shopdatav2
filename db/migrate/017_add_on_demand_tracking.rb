class AddOnDemandTracking < ActiveRecord::Migration[8.0]
  def change
    add_column :scrape_metrics, :trigger_type, :string, limit: 20, default: 'on_demand'
    add_column :scrape_metrics, :triggered_by, :string, limit: 100
    add_column :categories, :last_bsr_collected_at, :timestamp
    add_column :categories, :last_movers_collected_at, :timestamp
    add_column :categories, :last_trends_collected_at, :timestamp
    add_column :categories, :last_social_collected_at, :timestamp
  end
end
