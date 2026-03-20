# frozen_string_literal: true

class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # Ensures consistent ordering across queries by default
  self.implicit_order_column = 'created_at'
end
