class AddPaApiSyncedAtToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :pa_api_synced_at, :timestamp
  end
end
