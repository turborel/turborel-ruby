# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    # The Turborel adapter's parts (RULES.md D2).
    module Turborel
      # ActiveRecord's error of each of the driver's failures it names
      # (RULES.md D2), by its SQLSTATE and, of an integrity constraint
      # violation, by the constraint its message names.
      module Failures
        # The error of each SQLSTATE.
        STATES = {
          "22001" => ValueTooLong, "22003" => RangeError, "40001" => SerializationFailure,
          "40002" => TransactionRollbackError, "TB920" => QueryCanceled
        }.freeze

        # The error of an integrity constraint violation, by what its message
        # names.
        CONSTRAINTS = [
          [/\A(?:PRIMARY KEY|UNIQUE) /, RecordNotUnique], [/FOREIGN KEY/, InvalidForeignKey],
          [/ is NOT NULL\z/, NotNullViolation]
        ].freeze

        # The error class of +error+, or nil of one ActiveRecord's own
        # StatementInvalid stands for.
        #
        # @param error [::Turborel::Error]
        # @return [Class, nil]
        def self.kind(error)
          state = error.sqlstate
          return ConnectionFailed if state.start_with?("08")
          return STATES[state] unless state == "23000"

          CONSTRAINTS.find { |pattern, _| pattern.match?(error.message) }&.last
        end
      end
    end
  end
end
