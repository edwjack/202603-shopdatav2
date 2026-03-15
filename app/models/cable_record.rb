class CableRecord < ActiveRecord::Base
  self.abstract_class = true

  connects_to database: { writing: :cable }
end
