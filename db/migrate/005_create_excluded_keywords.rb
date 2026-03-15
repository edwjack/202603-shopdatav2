class CreateExcludedKeywords < ActiveRecord::Migration[8.0]
  def change
    create_table :excluded_keywords do |t|
      t.string :keyword, limit: 200, null: false
      t.string :category_pattern, limit: 100
      t.string :reason, limit: 500
      t.boolean :active, default: true
      t.timestamps
    end
    add_index :excluded_keywords, :keyword
  end
end
