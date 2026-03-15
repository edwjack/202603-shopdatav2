class CreateSourcingBatches < ActiveRecord::Migration[8.0]
  def change
    create_table :sourcing_batches do |t|
      t.references :category, null: false, foreign_key: true
      t.string :phase, limit: 20, null: false
      t.string :status, limit: 20, default: 'pending'
      t.integer :total_count, default: 0
      t.integer :processed_count, default: 0
      t.timestamp :started_at
      t.timestamp :completed_at
      t.timestamps
    end
    add_index :sourcing_batches, [:category_id, :phase]
  end
end
