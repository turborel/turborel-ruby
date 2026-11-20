# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    # The Turborel adapter's parts (RULES.md D2).
    module Turborel
      # How Turborel's ALTER TABLE is written: a foreign key dropped
      # RESTRICT, as its drop behavior must be named.
      class SchemaCreation < ConnectionAdapters::SchemaCreation
        private

        # DROP CONSTRAINT of a foreign key, RESTRICT.
        def visit_DropForeignKey(name) = "DROP CONSTRAINT #{quote_column_name(name)} RESTRICT"
      end
    end
  end
end
