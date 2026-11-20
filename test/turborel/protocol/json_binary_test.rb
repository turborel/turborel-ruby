# frozen_string_literal: true

require "test_helper"

module Turborel
  module Protocol
    # A JSON value's stored form, written.
    class JsonBinaryTest < Minitest::Test
      include TestSupport

      # Verifies: [PROTOCOL Values] a JSON document is a version octet, 1,
      # then its root node: 0 null, 1 false, 2 true.
      def test_document_and_constant_nodes
        assert_equal hex("01 00"), JsonBinary.encode(nil)
        assert_equal hex("01 01"), JsonBinary.encode(false)
        assert_equal hex("01 02"), JsonBinary.encode(true)
      end

      # Verifies: [PROTOCOL Values] an exact number is written in the
      # narrowest of its encodings: 3 integer i64, 4 decimal of units i64 and
      # scale u8, 5 wide decimal of units i128 and scale u32.
      def test_numbers_take_their_narrowest_node
        assert_equal hex("01 03 FFFFFFFFFFFFFFFF"), JsonBinary.encode(-1)
        assert_equal hex("01 04 0F00000000000000 01"), JsonBinary.encode(BigDecimal("1.5"))
        assert_equal hex("01 05 0000000000000080 0000000000000000 00000000"), JsonBinary.encode(2**63)
        assert_equal hex("01 05 0100000000000000 0000000000000000 00010000"), JsonBinary.encode(BigDecimal("1e-256"))
        assert_fails(OUT_OF_RANGE) { JsonBinary.encode(2**127) }
        assert_fails(OUT_OF_RANGE) { JsonBinary.encode(BigDecimal("NaN")) }
      end

      # Verifies: [PROTOCOL Values] 6 a DECFLOAT, coefficient i128 and
      # exponent i32; 7 an approximate number, f64 bits; 8 a string, octets
      # u32 then UTF-8; 9 a datetime, moment u8, UTC i64, zone i16, zoned u8,
      # precision u8.
      def test_other_scalar_nodes
        assert_equal hex("01 06 F1FFFFFFFFFFFFFFFFFFFFFFFFFFFFFF FDFFFFFF"),
                     JsonBinary.encode(DecFloat.new(coefficient: -15, exponent: -3))
        assert_equal hex("01 07 000000000000F83F"), JsonBinary.encode(1.5)
        assert_equal hex("01 08 02000000 C3A9"), JsonBinary.encode("é")
        assert_equal hex("01 08 01000000 61"), JsonBinary.encode(:a)
        stamp = Datetime.new(moment: :timestamp, utc: 1, zone: -60, zoned: true, precision: 3)

        assert_equal hex("01 09 02 0100000000000000 C4FF 01 03"), JsonBinary.encode(stamp)
        assert_fails(OUT_OF_RANGE) { JsonBinary.encode(DecFloat.new(coefficient: 10, exponent: 0)) }
        assert_fails(UNSUPPORTED) { JsonBinary.encode(stamp.with(moment: :week)) }
      end

      # Verifies: [PROTOCOL Values] 10 an array: count u32, size u32, each
      # element's offset u32 from the first, then the elements.
      def test_array_node
        assert_equal hex("01 0A 02000000 0F000000 00000000 09000000 03 0100000000000000 08 01000000 61"),
                     JsonBinary.encode([1, "a"])
        assert_equal hex("01 0A 00000000 00000000"), JsonBinary.encode([])
      end

      # Verifies: [PROTOCOL Values] 11 an object: count, size, each member's
      # offset in key order, then the members in written order, each its key
      # and value; the directory sorted by key octets, those of one key in
      # written order.
      def test_object_node_and_its_directory
        bytes = JsonBinary.encode({ "b" => 1, "a" => true })

        assert_equal hex("01 0B 02000000 14000000 0E000000 00000000 01000000 62 03 0100000000000000 01000000 61 02"),
                     bytes
        assert_equal hex("01 0B 00000000 00000000"), JsonBinary.encode({})
        assert_equal({ "b" => 1, "a" => true }, JsonBinary.decode(bytes))
      end

      # Verifies: [PROTOCOL Values] a value no JSON item holds, a key that is
      # not a string, or arrays nested deeper than 128 are refused before
      # they are sent (SQLSTATE 07006).
      def test_values_no_item_holds_are_refused
        assert_fails(UNSUPPORTED) { JsonBinary.encode(Object.new) }
        assert_fails(UNSUPPORTED) { JsonBinary.encode({ 1 => 2 }) }
        deep = nil
        130.times { deep = [deep] }
        assert_fails(UNSUPPORTED) { JsonBinary.encode(deep) }
      end
    end
  end
end
