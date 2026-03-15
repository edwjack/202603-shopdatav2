class QueueRecord < ActiveRecord::Base
  self.abstract_class = true

  connects_to database: { writing: :queue }
end
