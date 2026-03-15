ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Oracle ADB shared schema — run tests sequentially
    parallelize(workers: 1)

    # Add more helper methods to be used by all tests here...
  end
end
