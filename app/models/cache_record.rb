class CacheRecord < ActiveRecord::Base
  self.abstract_class = true

  connects_to database: { writing: :cache }
end
