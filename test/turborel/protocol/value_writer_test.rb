# frozen_string_literal: true

require "test_helper"

module Turborel
  module Protocol
    # Ruby values written as the protocol's values.
    class ValueWriterTest < Minitest::Test
      include TestSupport

      def bytes(value) = writer.tap { |w| ValueWriter.write(w, value) }.to_s

      def round_trip(value) = ValueReader.read(reader(bytes(value)))

      # Verifies: [PROTOCOL Values] nil is tag 0; a String tag 1, or tag 6 if
      # its encoding is binary; true and false tag 14.
      def test_null_strings_and_truth_values
        assert_equal hex("00"), bytes(nil)
        assert_equal hex("01 02000000 C3A9"), bytes("é")
        assert_equal hex("06 01000000 FF"), bytes("\xFF".b)
        assert_equal hex("0E 01 0E 00".delete(" ")), bytes(true) + bytes(false)
      end

      # Verifies: [PROTOCOL A worked example] the exact number 1 is tag 2,
      # units 1 as i128, scale 0.
      def test_integer_one_is_the_worked_examples_bytes
        assert_equal hex("02 01#{"00" * 15} 00000000"), bytes(1)
      end

      # Verifies: [PROTOCOL Values] an exact number reaches BigDecimal and
      # back with no loss, the full i128 range and large scales too.
      def test_exact_numbers_round_trip
        [0, -1, (2**127) - 1, -(2**127), BigDecimal("-123.45"), BigDecimal("0.000001"), BigDecimal("1e30"),
         BigDecimal("#{(2**127) - 1}e-38"), BigDecimal("-1e-4294967295")].each do |number|
          assert_equal number, round_trip(number)
        end
        assert_equal hex("02 39300000#{"00" * 12} 02000000"), bytes(BigDecimal("123.45"))
        assert_equal hex("02 #{"00" * 16} 00000000"), bytes(BigDecimal("-0"))
        assert_equal hex("02 96#{"00" * 15} 02000000"), bytes(Decimal.new(units: 150, scale: 2))
      end

      # Verifies: [DESIGN] D8 a number no exact number holds is refused with
      # SQLSTATE 22003, never rounded.
      def test_numbers_out_of_range_are_refused
        assert_fails(OUT_OF_RANGE) { bytes(2**127) }
        assert_fails(OUT_OF_RANGE) { bytes(BigDecimal("1e40")) }
        assert_fails(OUT_OF_RANGE) { bytes(BigDecimal("1e100000")) }
        assert_fails(OUT_OF_RANGE) { bytes(BigDecimal("NaN")) }
        assert_fails(OUT_OF_RANGE) { bytes(BigDecimal("Infinity")) }
      end

      # Verifies: [PROTOCOL Values] a Float is tag 3, its bits; NaN and -0.0
      # kept.
      def test_floats_keep_their_bits
        assert_equal hex("03 000000000000E0BF"), bytes(-0.5)
        assert_equal [-0.0].pack("E"), [round_trip(-0.0)].pack("E")
        assert_predicate round_trip(Float::NAN), :nan?
      end

      # Verifies: [PROTOCOL Values] each of the driver's value classes is
      # written under its own tag and reads back as it was.
      def test_value_classes_round_trip
        values.each { |value| assert_equal value, round_trip(value), value.inspect }
      end

      def values
        [Datetime.new(moment: :timestamp, utc: -1, zone: -779, zoned: true, precision: 6),
         Datetime.new(moment: :date, utc: 0, zone: 0, zoned: false, precision: 0),
         Interval.new(start: :day, finish: :second, leading: 2, fraction: 6, units: 2**100),
         DecFloat.new(coefficient: -15, exponent: -3), [1, [nil, "a"]], Row.new(values: [true]),
         Multiset.new(values: [nil]), Structured.new(schema: "S", name: "T", attributes: [1]),
         Reference.new(octets: "\x01".b), Json.new(value: { "k" => [1, Decimal.new(units: 15, scale: 1), nil] }),
         Xml.new(text: "<a/>"),
         Uuid.new(octets: "\x00".b * 16), Extension.new(name: "P", text: "t", bytes: "\x02".b),
         Lob.new(kind: :character, data: "é", locator: nil, octets: 2, characters: 1),
         Lob.new(kind: :binary, data: nil, locator: 3, octets: 9, characters: 0)]
      end

      # Verifies: [PROTOCOL Values] a timestamp is zoned u8, precision u8,
      # the displacement's i16 bits in a u32, then UTC microseconds.
      def test_timestamp_bytes
        stamp = Datetime.new(moment: :timestamp, utc: 1_000_000_000_000_000, zone: 840, zoned: true, precision: 6)

        assert_equal hex("0B 01 06 48030000 0080C6A47E8D0300"), bytes(stamp)
        assert_fails(OUT_OF_RANGE) { bytes(stamp.with(zone: 2**15)) }
        assert_fails(DATA_EXCEPTION) { bytes(stamp.with(moment: :week)) }
      end

      # Verifies: [PROTOCOL Values] a value of no class the driver sends, a
      # malformed one, or one nested deeper than 16 is refused before it is
      # sent (SQLSTATE 22000, 22003 of a number, 0A000 nested too deep).
      def test_values_that_cannot_be_sent_are_refused
        assert_fails(DATA_EXCEPTION) { bytes(Object.new) }
        assert_fails(DATA_EXCEPTION) { bytes(:symbol) }
        assert_fails(DATA_EXCEPTION) do
          bytes(Interval.new(start: :week, finish: :day, leading: 2, fraction: 0, units: 0))
        end
        assert_fails(DATA_EXCEPTION) { bytes(Lob.new(kind: :text, data: "", locator: nil, octets: 0, characters: 0)) }
        assert_fails(OUT_OF_RANGE) { bytes(DecFloat.new(coefficient: 10, exponent: 0)) }
        assert_fails(OUT_OF_RANGE) { bytes(Uuid.new(octets: "\x00".b * 15)) }
        nested = nil
        17.times { nested = [nested] }
        assert_fails(BEYOND) { bytes(nested) }
      end

      # Verifies: [PROTOCOL Values] a value of a subclass of a class the
      # driver sends is written as that class's.
      def test_subclasses_are_written_as_their_class
        subclass = Class.new(String)

        assert_equal bytes("x"), bytes(subclass.new("x"))
      end
    end
  end
end
