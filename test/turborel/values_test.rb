# frozen_string_literal: true

require "test_helper"

module Turborel
  # The driver's value classes.
  class ValuesTest < Minitest::Test
    # Verifies: [PROTOCOL Values] a value class compares by its fields, so a
    # value read back equals the value written.
    def test_values_compare_by_their_fields
      assert_equal Uuid.new(octets: "a" * 16), Uuid.new(octets: "a" * 16)
      refute_equal Row.new(values: [1]), Multiset.new(values: [1])
      assert_equal DataType.new(kind: :json, params: {}), DataType.new(kind: :json, params: {})
      assert_predicate Lob.new(kind: :binary, data: nil, locator: 1, octets: 0, characters: 0), :frozen?
    end
  end
end
