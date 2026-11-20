# frozen_string_literal: true

require "test_helper"

module Turborel
  # A failure and its diagnostics, as values.
  class FailureTest < Minitest::Test
    # Verifies: [PROTOCOL Errors and notices] a failure's diagnostics are its
    # severity, detail, hint, context, schema, table, column, data type and
    # constraint, each nil where it says nothing.
    def test_failures_compare_by_their_fields
      diagnostics = Diagnostics.new(severity: "WARNING", detail: nil, hint: nil, context: nil, schema: nil, table: nil,
                                    column: nil, data_type: nil, constraint: nil)
      failure = Failure.new(sqlcode: 0, sqlstate: "01000", message: "w", rule: nil, position: nil, active: false,
                            diagnostics:)

      assert_equal failure, failure.with(message: "w")
      refute_equal failure, failure.with(active: true)
      assert_predicate failure, :frozen?
    end
  end
end
