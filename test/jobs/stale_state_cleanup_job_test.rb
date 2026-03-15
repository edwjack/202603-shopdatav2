require "test_helper"

class StaleStateCleanupJobTest < ActiveSupport::TestCase
  setup do
    @category = Category.create!(
      name: 'Cleanup Test', slug: 'cleanup-test', status: 'tracking', active: true
    )
  end

  teardown do
    SourcingBatch.where(category: @category).delete_all
    @category.reload
    @category.destroy
  end

  test "resets categories stuck in sourcing for > 2 hours" do
    @category.update!(status: 'sourcing', updated_at: 3.hours.ago)
    StaleStateCleanupJob.perform_now
    @category.reload
    assert_equal 'tracking', @category.status
  end

  test "does not reset recently sourcing categories" do
    @category.update!(status: 'sourcing', updated_at: 30.minutes.ago)
    StaleStateCleanupJob.perform_now
    @category.reload
    assert_equal 'sourcing', @category.status
  end

  test "marks stale in_progress batches as failed" do
    batch = SourcingBatch.create!(
      category: @category,
      phase: 'url_list',
      status: 'in_progress',
      started_at: 3.hours.ago
    )
    StaleStateCleanupJob.perform_now
    batch.reload
    assert_equal 'failed', batch.status
    assert_not_nil batch.completed_at
  end

  test "does not affect recently started batches" do
    batch = SourcingBatch.create!(
      category: @category,
      phase: 'url_list',
      status: 'in_progress',
      started_at: 30.minutes.ago
    )
    StaleStateCleanupJob.perform_now
    batch.reload
    assert_equal 'in_progress', batch.status
  end
end
