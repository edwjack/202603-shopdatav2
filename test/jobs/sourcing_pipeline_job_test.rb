require "test_helper"

class SourcingPipelineJobTest < ActiveSupport::TestCase
  setup do
    ENV['MOCK_EXTERNAL_APIS'] = 'true'
    @category = Category.create!(name: 'Pet Supplies', slug: 'pet-supplies', status: 'tracking', active: true)
  end

  teardown do
    SourcingBatch.where(category: @category).delete_all
    Product.where(category: @category).delete_all
    AsinUrl.where(category: @category).delete_all
    @category.reload
    @category.destroy
  end

  test "full pipeline creates 4 sourcing batches" do
    SourcingPipelineJob.perform_now(@category.id)
    batches = SourcingBatch.where(category: @category)
    assert_equal 4, batches.count
    assert_equal %w[url_list scrapling_collect filter final_filter], batches.order(:id).pluck(:phase)
    assert batches.all? { |b| b.status == 'completed' }
  end

  test "pipeline sets category status to completed" do
    SourcingPipelineJob.perform_now(@category.id)
    @category.reload
    assert_equal 'completed', @category.status
  end

  test "pipeline creates products" do
    SourcingPipelineJob.perform_now(@category.id)
    assert Product.where(category: @category).count > 0
  end

  test "concurrent guard skips if already sourcing" do
    @category.update!(status: 'sourcing')
    SourcingPipelineJob.perform_now(@category.id)
    # No batches created because pipeline was skipped
    assert_equal 0, SourcingBatch.where(category: @category).count
    # Status unchanged
    @category.reload
    assert_equal 'sourcing', @category.status
  end

  test "batches have meaningful processed_count" do
    SourcingPipelineJob.perform_now(@category.id)
    filter_batch = SourcingBatch.find_by(category: @category, phase: 'filter')
    assert_not_nil filter_batch.processed_count
    assert filter_batch.processed_count >= 0
  end
end
