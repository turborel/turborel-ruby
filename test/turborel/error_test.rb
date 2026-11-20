# frozen_string_literal: true

require "test_helper"

module Turborel
  # The driver's error.
  class ErrorTest < Minitest::Test
    include TestSupport

    # Verifies: [PROTOCOL Composite fields] an error carries its failure:
    # SQLCODE, SQLSTATE, message, rule, position, whether a transaction is
    # active, and its diagnostics.
    def test_error_carries_its_failure
      diagnostics = Diagnostics.new(severity: "ERROR", detail: nil, hint: nil, context: nil, schema: "S", table: "T",
                                    column: nil, data_type: nil, constraint: "K")
      failure = Failure.new(sqlcode: -201, sqlstate: "23000", message: "broken", rule: "X 1", position: 7, active: true,
                            diagnostics:)
      error = Error.new(failure)

      assert_equal [-201, "23000", "broken", "X 1", 7, true], [error.sqlcode, error.sqlstate, error.message, error.rule,
                                                               error.position, error.active]
      assert_equal "K", error.diagnostics&.constraint
      assert_same failure, error.failure
    end

    # Verifies: [PROTOCOL Errors and notices] the driver's own failures carry
    # turborel's conditions: a connection failure -919 and 08006, a value
    # the protocol cannot carry -301 and 22000, what is past turborel's
    # limits -900 and 0A000, misuse -910 and TB910.
    def test_driver_failures_carry_their_conditions
      assert_equal CONNECTION_FAILURE, [Error.connection_failure("x").sqlcode, Error.connection_failure("x").sqlstate]
      assert_equal OUT_OF_RANGE, [Error.out_of_range("x").sqlcode, Error.out_of_range("x").sqlstate]
      assert_equal DATA_EXCEPTION, [Error.data_exception("x").sqlcode, Error.data_exception("x").sqlstate]
      assert_equal BEYOND, [Error.beyond("x").sqlcode, Error.beyond("x").sqlstate]
      assert_equal MISUSED, [Error.misused("x").sqlcode, Error.misused("x").sqlstate]
      assert_equal "22021", Error.not_in_repertoire("x").sqlstate
      assert_nil Error.of(-1, "XX000", "m").diagnostics
    end
  end
end
