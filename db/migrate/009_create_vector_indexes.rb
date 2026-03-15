class CreateVectorIndexes < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL rescue nil
      CREATE VECTOR INDEX idx_recommendation_vector
      ON recommendations(insight_vector)
      ORGANIZATION NEIGHBOR PARTITIONS
      WITH DISTANCE COSINE
    SQL
    execute <<~SQL rescue nil
      CREATE VECTOR INDEX idx_product_title_vector
      ON products(title_vector)
      ORGANIZATION NEIGHBOR PARTITIONS
      WITH DISTANCE COSINE
    SQL
  end

  def down
    execute "DROP INDEX idx_recommendation_vector" rescue nil
    execute "DROP INDEX idx_product_title_vector" rescue nil
  end
end
