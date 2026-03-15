class RenamePaApiSyncedAt < ActiveRecord::Migration[8.0]
  def change
    rename_column :products, :pa_api_synced_at, :data_synced_at
  end
end
