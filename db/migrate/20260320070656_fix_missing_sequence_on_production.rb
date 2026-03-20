# frozen_string_literal: true

class FixMissingSequenceOnProduction < ActiveRecord::Migration[7.2]
    def up
      execute "CREATE SEQUENCE IF NOT EXISTS short_url_counter START 56800235584 INCREMENT 1 NO CYCLE;"
      
      execute "ALTER SEQUENCE short_url_counter CACHE 1000;"
    end

    def down
      execute "DROP SEQUENCE IF EXISTS short_url_counter;"
    end
end
