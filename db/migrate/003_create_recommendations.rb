class CreateRecommendations < ActiveRecord::Migration[8.0]
  def up
    create_table :recommendations do |t|
      t.references :category, null: false, foreign_key: true
      t.decimal :score, precision: 3, scale: 1, null: false
      t.text :score_breakdown, null: false
      t.text :insight
      t.text :risks
      t.text :action_items
      t.text :similar_pattern
      t.text :analysis_input
      t.string :status, limit: 20, default: 'pending'
      t.string :rejection_reason, limit: 500
      t.string :model_version, limit: 50
      t.integer :week_number
      t.timestamp :approved_at
      t.timestamps
    end
    add_index :recommendations, :status

    execute "ALTER TABLE recommendations ADD insight_vector VECTOR(768, FLOAT32)"
  end

  def down
    drop_table :recommendations
  end
end
