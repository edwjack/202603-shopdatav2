require "test_helper"

class CircuitBreakerTest < ActiveSupport::TestCase
  SERVICE = 'test_circuit_service'

  # Use a real memory store for circuit breaker tests (test env uses :null_store)
  setup do
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    CircuitBreaker.reset(SERVICE)
  end

  teardown do
    CircuitBreaker.reset(SERVICE)
    Rails.cache = @original_cache
  end

  test "check returns true when circuit is closed" do
    assert CircuitBreaker.check(SERVICE)
  end

  test "record_failure increments failure count" do
    CircuitBreaker.record_failure(SERVICE)
    status = CircuitBreaker.status(SERVICE)
    assert_equal 1, status[:failures]
    assert_equal false, status[:open]
  end

  test "circuit opens after MAX_FAILURES consecutive failures" do
    CircuitBreaker::MAX_FAILURES.times { CircuitBreaker.record_failure(SERVICE) }
    assert_equal false, CircuitBreaker.check(SERVICE)
    status = CircuitBreaker.status(SERVICE)
    assert status[:open]
  end

  test "record_success resets failure count" do
    2.times { CircuitBreaker.record_failure(SERVICE) }
    CircuitBreaker.record_success(SERVICE)
    status = CircuitBreaker.status(SERVICE)
    assert_equal 0, status[:failures]
    assert_equal false, status[:open]
  end

  test "reset clears all circuit state" do
    CircuitBreaker::MAX_FAILURES.times { CircuitBreaker.record_failure(SERVICE) }
    CircuitBreaker.reset(SERVICE)
    assert CircuitBreaker.check(SERVICE)
    status = CircuitBreaker.status(SERVICE)
    assert_equal 0, status[:failures]
    assert_equal false, status[:open]
  end

  test "status returns correct structure" do
    status = CircuitBreaker.status(SERVICE)
    assert status.key?(:failures)
    assert status.key?(:open)
    assert status.key?(:opened_at)
  end
end
