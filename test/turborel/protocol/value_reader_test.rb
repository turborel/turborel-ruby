# frozen_string_literal: true

require "test_helper"

module Turborel
  module Protocol
    # Values read from the bytes the protocol writes.
    class ValueReaderTest < Minitest::Test
      include TestSupport

      def value(bytes)
        fields = reader(bytes)
        read = ValueReader.read(fields)
        fields.finish
        read
      end

      # Verifies: [PROTOCOL Values] tag 0 is null, nothing after it; tag 1 a
      # character string, which a CHARACTER VARYING value is written as too.
      def test_null_and_character_strings
        assert_nil value(hex("00"))
        assert_equal "abc", value(hex("01 03000000 616263"))
        assert_equal Encoding::UTF_8, value(hex("01 02000000 C3A9")).encoding
      end

      # Verifies: [PROTOCOL Values] tag 2, an exact number: units i128 then
      # scale u32, units divided by ten to the scale, exactly, at the limits
      # of i128 and of scale.
      def test_exact_numbers
        assert_equal 1, value(hex("02 01#{"00" * 15} 00000000"))
        assert_equal BigDecimal("-123.45"), value(writer.u8(2).i128(-12_345).u32(2).to_s)
        assert_equal (2**127) - 1, value(writer.u8(2).i128((2**127) - 1).u32(0).to_s)
        assert_equal(-(2**127), value(writer.u8(2).i128(-(2**127)).u32(0).to_s))
        tiny = value(writer.u8(2).i128((2**127) - 1).u32(0xFFFF_FFFF).to_s)

        assert_equal BigDecimal("#{(2**127) - 1}e-4294967295"), tiny
        assert_kind_of BigDecimal, tiny
      end

      # Verifies: [PROTOCOL Values] tag 3, an approximate number, the bits of
      # an IEEE 754 double; NaN and -0.0 kept.
      def test_approximate_numbers_keep_their_bits
        assert_in_delta(-0.5, value(writer.u8(3).f64(-0.5).to_s))
        assert_predicate value(writer.u8(3).f64(Float::NAN).to_s), :nan?
        assert_equal [-0.0].pack("E"), [value(writer.u8(3).f64(-0.0).to_s)].pack("E")
        assert_equal Float::INFINITY, value(writer.u8(3).f64(Float::INFINITY).to_s)
      end

      # Verifies: [PROTOCOL Values] tag 4, a plug-in's value, its type's
      # name, its text and its bytes, kept as they came; tag 6 a binary
      # string; tag 24 a reference's bytes.
      def test_plugin_values_binary_strings_and_references
        assert_equal Extension.new(name: "POINT", text: "(1 2)", bytes: "\x01\x02".b),
                     value(writer.u8(4).str("POINT").str("(1 2)").bytes("\x01\x02").to_s)
        binary = value(hex("06 02000000 00FF"))

        assert_equal "\x00\xFF".b, binary
        assert_equal Encoding::BINARY, binary.encoding
        assert_equal Reference.new(octets: "\x09".b), value(hex("18 01000000 09"))
      end

      # Verifies: [PROTOCOL Values] tags 8, 9 and 11, a date, a time and a
      # timestamp: zoned u8, precision u8, the zone's displacement in minutes
      # as an i16 in a u32, the instant in UTC microseconds, i64 as u64.
      def test_datetimes
        stamp = value(hex("0B 01 06 48030000 0080C6A47E8D0300"))

        assert_equal Datetime.new(moment: :timestamp, utc: 1_000_000_000_000_000, zone: 840, zoned: true, precision: 6),
                     stamp
        west = value(writer.u8(9).u8(0).u8(0).u32(0xFFFF - 778).i64(-1).to_s)

        assert_equal [:time, -779, false, -1], [west.moment, west.zone, west.zoned, west.utc]
        assert_equal :date, value(writer.u8(8).u8(0).u8(0).u32(0).i64(0).to_s).moment
        assert_fails { value(writer.u8(11).u8(0).u8(0).u32(0x1_0000).i64(0).to_s) }
      end

      # Verifies: [PROTOCOL Values] tag 13, an interval: its qualifier as the
      # INTERVAL type writes it, then units i128, of every qualifier.
      def test_intervals_of_every_qualifier
        fields = Types::FIELDS
        fields.each_with_index do |start, first|
          fields.each_with_index.select { |_, last| last >= first }.each do |finish, last|
            read = value(writer.u8(13).u32(first).u32(last).u32(9).u32(6).i128(-(2**127)).to_s)

            assert_equal Interval.new(start:, finish:, leading: 9, fraction: 6, units: -(2**127)), read
          end
        end
      end

      # Verifies: [PROTOCOL Values] tag 14, a truth value: 0 false, 1 true,
      # any other byte a value that cannot be taken (TB916).
      def test_truth_values
        refute value(hex("0E 00"))
        assert value(hex("0E 01"))
        assert_fails(CORRUPT) { value(hex("0E 02")) }
      end

      # Verifies: [PROTOCOL Values] tag 15, a decimal floating point number:
      # coefficient i128 then exponent i32 as u32, in its one form.
      def test_decfloats
        assert_equal DecFloat.new(coefficient: -15, exponent: -3), value(writer.u8(15).i128(-15).i32(-3).to_s)
        assert_equal DecFloat.new(coefficient: 0, exponent: 0), value(writer.u8(15).i128(0).i32(0).to_s)
        max = (10**34) - 1

        assert_equal DecFloat.new(coefficient: max, exponent: 6144 - 33), value(writer.u8(15).i128(max).i32(6111).to_s)
        assert_fails { value(writer.u8(15).i128(10).i32(0).to_s) }
        assert_fails { value(writer.u8(15).i128(0).i32(1).to_s) }
        assert_fails { value(writer.u8(15).i128(10**34).i32(0).to_s) }
        assert_fails { value(writer.u8(15).i128(1).i32(6145).to_s) }
      end

      # Verifies: [PROTOCOL Values] tags 16, 17, 22 and 23: an array, a row,
      # a multiset and a structured value, each a list of values, nested.
      def test_nested_values
        array = value(writer.u8(16).u32(2).u8(16).u32(1).u8(0).u8(14).u8(1).to_s)

        assert_equal [[nil], true], array
        assert_equal Row.new(values: ["a", nil]), value(writer.u8(17).u32(2).u8(1).str("a").u8(0).to_s)
        assert_equal Multiset.new(values: [1]), value(writer.u8(22).u32(1).u8(2).i128(1).u32(0).to_s)
        assert_equal Structured.new(schema: "S", name: "T", attributes: [false]),
                     value(writer.u8(23).str("S").str("T").u32(1).u8(14).u8(0).to_s)
      end

      # Verifies: [DESIGN] D1 values nest at most 16 deep, as turborel bounds
      # them; deeper fails the connection.
      def test_value_nesting_is_bounded
        deep = writer.tap { |w| 16.times { w.u8(16).u32(1) } }.u8(0).to_s
        too_deep = writer.tap { |w| 17.times { w.u8(16).u32(1) } }.u8(0).to_s

        assert_equal [[[[[[[[[[[[[[[[nil]]]]]]]]]]]]]]]], value(deep)
        assert_fails { value(too_deep) }
      end

      # Verifies: [PROTOCOL Values] tags 20 and 21: a large object whole, its
      # kind then its octets, UTF-8 of a character one; or by locator, its
      # kind, locator u32, octets u64 and characters u64.
      def test_large_objects
        clob = value(hex("14 00 02000000 C3A9"))

        assert_equal Lob.new(kind: :character, data: "é", locator: nil, octets: 2, characters: 1), clob
        assert_equal Lob.new(kind: :binary, data: "\x07".b, locator: nil, octets: 1, characters: nil),
                     value(hex("14 01 01000000 07"))
        assert_equal Lob.new(kind: :binary, data: nil, locator: 9, octets: 2**33, characters: 0),
                     value(writer.u8(21).u8(1).u32(9).u64(2**33).u64(0).to_s)
        assert_fails { value(hex("14 00 01000000 FF")) }
        assert_fails { value(hex("14 02 00000000")) }
      end

      # Verifies: [PROTOCOL Values] tag 26, XML, its serialization as
      # CONTENT; tag 27, a UUID, bytes of 16 octets.
      def test_xml_and_uuids
        assert_equal Xml.new(text: "<a/>"), value(writer.u8(26).str("<a/>").to_s)
        octets = (1..16).to_a.pack("C*")

        assert_equal Uuid.new(octets:), value(writer.u8(27).bytes(octets).to_s)
        assert_fails { value(writer.u8(27).bytes("\x01" * 15).to_s) }
      end

      # Verifies: [PROTOCOL Values] tag 25, JSON, the stored form in bytes;
      # a tag no value has fails the connection; a large object's stored
      # tag is a value that cannot be taken.
      def test_json_and_unknown_tags
        assert_equal Json.new(value: { "a" => [1, nil] }),
                     value(writer.u8(25).bytes(JsonBinary.encode({ "a" => [1, nil] })).to_s)
        [5, 7, 10, 12, 28].each { |tag| assert_fails { value(writer.u8(tag).to_s) } }
        [18, 19].each { |tag| assert_fails(CORRUPT) { value(writer.u8(tag).to_s) } }
      end

      # Verifies: [PROTOCOL Values] the tags of CHARACTER VARYING, BINARY
      # VARYING and the datetimes WITH TIME ZONE read as turborel-protocol's
      # reader reads them, as tags 1, 6, 9 and 11; the large objects' stored
      # tags, 18 and 19, refused as values that cannot be taken (TB916,
      # RULES.md D8).
      def test_tags_the_page_does_not_list
        datetime = writer.u8(1).u8(6).u32(60).u64(5).to_s

        assert_equal ["ab", "\x01".b], [value(writer.u8(5).str("ab").to_s), value(writer.u8(7).bytes("\x01").to_s)]
        assert_equal(%i[time timestamp], [10, 12].map { |tag| value(writer.u8(tag).raw(datetime).to_s).moment })
        [18, 19].each { |tag| assert_fails(CORRUPT) { value(writer.u8(tag).u8(0).bytes("x").to_s) } }
      end
    end
  end
end
