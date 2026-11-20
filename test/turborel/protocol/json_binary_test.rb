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

      # Verifies: [PROTOCOL JSON values] a decimal keeps the scale it was
      # written with, so 1.50 is units 150 and scale 2, in the narrowest
      # node that holds it.
      def test_a_decimal_keeps_its_scale
        assert_equal hex("01 04 9600000000000000 02"), JsonBinary.encode(Decimal.new(units: 150, scale: 2))
        assert_equal hex("01 03 0700000000000000"), JsonBinary.encode(Decimal.new(units: 7, scale: 0))
        assert_equal hex("01 05 9600000000000000 0000000000000000 00010000"),
                     JsonBinary.encode(Decimal.new(units: 150, scale: 256))
      end

      # Verifies: [PROTOCOL JSON values] a document is at most 256 MiB: one
      # longer is refused, the bound taken lower here.
      def test_a_document_is_bounded
        assert_equal 14, JsonBinary.encode("x" * 8, most: 14).bytesize
        assert_fails(BEYOND) { JsonBinary.encode("x" * 9, most: 14) }
        assert_equal 1 << 28, JsonBinary::MAX_DOCUMENT_OCTETS
      end

      # Verifies: [PROTOCOL JSON values] the page's examples: {"a":[1,"x"]}
      # is its 51 octets, and in {"b":1,"a":2} the members keep their order
      # while the directory puts a first, at 14, then b, at 0.
      def test_the_pages_examples
        example = hex("01 0B 01000000 25000000 00000000 01000000 61 0A 02000000 0F000000 00000000 09000000 " \
                      "03 0100000000000000 08 01000000 78")

        assert_equal 51, example.bytesize
        assert_equal example, JsonBinary.encode({ "a" => [1, "x"] })
        assert_equal({ "a" => [1, "x"] }, JsonBinary.decode(example))
        both = JsonBinary.encode({ "b" => 1, "a" => 2 })

        assert_equal hex("0E000000 00000000"), both.byteslice(10, 8)
        assert_equal %w[b a], JsonBinary.decode(both).keys
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
        assert_fails(DATA_EXCEPTION) { JsonBinary.encode(stamp.with(moment: :week)) }
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
      # they are sent (SQLSTATE 22000, 0A000 nested too deep).
      def test_values_no_item_holds_are_refused
        assert_fails(DATA_EXCEPTION) { JsonBinary.encode(Object.new) }
        assert_fails(DATA_EXCEPTION) { JsonBinary.encode({ 1 => 2 }) }
        deep = nil
        130.times { deep = [deep] }
        assert_fails(BEYOND) { JsonBinary.encode(deep) }
      end
    end
  end
end
