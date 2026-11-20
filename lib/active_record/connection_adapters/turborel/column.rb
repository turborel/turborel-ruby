# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    # The Turborel adapter's parts (RULES.md D2).
    module Turborel
      # A column of a table, an identity column given its values by the
      # database.
      class Column < ConnectionAdapters::Column
        # A column, an identity column if +identity+.
        def initialize(*, identity: false, **)
          super(*, **)
          @identity = identity
        end

        # @return [Boolean] whether the database gives the column its values
        def auto_incremented_by_db? = @identity

        # @return [Boolean] whether the column is a BIGINT's, as Turborel
        #   names the type in capitals
        def bigint? = /\ABIGINT\b/i.match?(sql_type)

        # @return [Boolean] whether the column is an identity column
        def identity? = @identity
      end
    end
  end
end
