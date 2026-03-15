module CircuitBreaker
  MAX_FAILURES = 3
  RESET_TIMEOUT = 1.hour

  def self.check(service_name)
    opened_at = Rails.cache.read("circuit_breaker:#{service_name}:opened_at")
    return true if opened_at.nil?  # Circuit closed, proceed

    if Time.current - opened_at > RESET_TIMEOUT
      reset(service_name)
      return true  # Half-open: try again
    end

    false  # Circuit open, skip
  end

  def self.record_failure(service_name)
    failures_key = "circuit_breaker:#{service_name}:failures"
    current = Rails.cache.read(failures_key) || 0
    count = current + 1
    Rails.cache.write(failures_key, count, expires_in: 24.hours)
    if count >= MAX_FAILURES
      Rails.cache.write(
        "circuit_breaker:#{service_name}:opened_at",
        Time.current,
        expires_in: RESET_TIMEOUT + 1.minute
      )
      Rails.logger.error "[CircuitBreaker] #{service_name} OPENED after #{count} consecutive failures"
    end
  end

  def self.record_success(service_name)
    reset(service_name)
  end

  def self.reset(service_name)
    Rails.cache.delete("circuit_breaker:#{service_name}:failures")
    Rails.cache.delete("circuit_breaker:#{service_name}:opened_at")
  end

  def self.status(service_name)
    failures = Rails.cache.read("circuit_breaker:#{service_name}:failures") || 0
    opened_at = Rails.cache.read("circuit_breaker:#{service_name}:opened_at")
    { failures: failures, open: opened_at.present?, opened_at: opened_at }
  end
end
