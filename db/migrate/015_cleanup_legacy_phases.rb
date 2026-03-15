class CleanupLegacyPhases < ActiveRecord::Migration[8.0]
  def up
    execute <<-SQL
      UPDATE sourcing_batches SET phase = 'scrapling_collect' WHERE phase IN ('pa_api', 'scrape')
    SQL
  end

  def down
    # No rollback needed for data-only migration
  end
end
