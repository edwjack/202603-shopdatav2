class AddRecommendationWeekUniqueIndex < ActiveRecord::Migration[8.0]
  def up
    # Convert existing week_number values from plain week (1-53) to YYYYWW format
    execute <<~SQL
      UPDATE recommendations
      SET week_number = TO_NUMBER(TO_CHAR(created_at, 'IYYYIW'))
      WHERE week_number IS NOT NULL AND week_number < 10000
    SQL

    add_index :recommendations, [:category_id, :week_number],
              unique: true, name: 'idx_recommendations_category_week'
  end

  def down
    remove_index :recommendations, name: 'idx_recommendations_category_week'
  end
end
