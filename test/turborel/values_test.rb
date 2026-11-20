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

    # Verifies: [CLIENT UUIDs] a UUID's text, and a UUID made of its text as
    # turborel's CAST reads it: 32 hexadecimal digits in either case, its
    # spaces trimmed, braced or not, a hyphen allowed after each group of
    # four but the last; none of other text.
    def test_uuid_text
      text = "919108f7-52d1-4320-9bac-f847db4148a8"
      octets = ["919108f752d143209bacf847db4148a8"].pack("H*")

      assert_equal text, Uuid.new(octets:).text
      [text, " {919108F7-52D1-4320-9BAC-F847DB4148A8}\t", "919108f752d143209bacf847db4148a8",
       "9191-08f7-52d1-4320-9bac-f847-db41-48a8"].each { |form| assert_equal octets, Uuid.parse(form)&.octets }
      ["", "{}", "919108f7--52d1-4320-9bac-f847db4148a8", "-919108f752d143209bacf847db4148a8",
       "919108f752d143209bacf847db4148a8-", "919108f-752d143209bacf847db4148a8",
       "919108f752d143209bacf847db4148a", "919108f752d143209bacf847db4148a8a",
       "g19108f752d143209bacf847db4148a8"].each { |form| assert_nil Uuid.parse(form) }
    end

    # Verifies: [PROTOCOL JSON values] a decimal keeps its scale: its text
    # has the scale's digits after the point, its BigDecimal the number.
    def test_decimal_forms
      texts = [[150, 2], [-5, 2], [7, 0], [0, 3]].map { |units, scale| Decimal.new(units:, scale:).to_s }

      assert_equal %w[1.50 -0.05 7 0.000], texts
      assert_equal BigDecimal("-0.05"), Decimal.new(units: -5, scale: 2).to_d
    end
  end
end
