# frozen_string_literal: true

require "test_helper"

module Turborel
  module Protocol
    # A JSON value's stored form, read and checked whole.
    class JsonDecoderTest < Minitest::Test
      include TestSupport

      def decode(text) = JsonBinary.decode(hex(text))

      # Verifies: [PROTOCOL Values] each node is read as the Ruby value it
      # holds, every scalar and container at once.
      def test_nodes_are_read_as_ruby_values
        value = { "n" => nil, "f" => false, "t" => true, "i" => -(2**63),
                  "d" => Decimal.new(units: -5, scale: 2), "w" => 2**100,
                  "x" => DecFloat.new(coefficient: 7, exponent: 2), "a" => -0.0, "s" => "é",
                  "m" => Datetime.new(moment: :date, utc: 86_400_000_000, zone: 0, zoned: false, precision: 0),
                  "l" => [[], {}, [1]] }
        read = JsonBinary.decode(JsonBinary.encode(value))

        assert_equal value.except("a"), read.except("a")
        assert_equal [-0.0].pack("E"), [read.fetch("a")].pack("E")
        assert_equal value.keys, read.keys
      end

      # Verifies: [PROTOCOL JSON values] a decimal or wide decimal of scale
      # 0 is an Integer, of a greater scale a Decimal keeping the scale it
      # was written with: 1.50 is units 150 and scale 2.
      def test_decimals_keep_their_scale
        assert_equal 15, decode("01 04 0F00000000000000 00")
        assert_equal Decimal.new(units: 15, scale: 1), decode("01 05 0F#{"00" * 15} 01000000")
        assert_equal Decimal.new(units: 150, scale: 2), decode("01 04 9600000000000000 02")
        assert_equal "1.50", decode("01 04 9600000000000000 02").to_s
      end

      # Verifies: [PROTOCOL Values] of members of one key, the first written
      # is kept, as a member accessor takes it.
      def test_first_member_of_a_key_is_kept
        assert_equal({ "a" => true }, decode("01 0B 02000000 0C000000 00000000 06000000 01000000 61 02 01000000 61 01"))
      end

      # Verifies: [PROTOCOL Values] another version than 1, octets after the
      # root, or a node past the document fails the connection.
      def test_damaged_documents_fail
        ["02 00", "01", "", "01 00 00", "01 03 0100", "01 08 05000000 61", "01 0C"].each do |text|
          assert_fails { decode(text) }
        end
      end

      # Verifies: [PROTOCOL Values] an element not where its offset says, or
      # an array whose size is not its elements', fails the connection.
      def test_damaged_arrays_fail
        assert_fails { decode("01 0A 01000000 01000000 01000000 00") }
        assert_fails { decode("01 0A 01000000 02000000 00000000 00 00") }
      end

      # Verifies: [PROTOCOL Values] an object whose size is not its members',
      # whose directory names no member, or is not sorted by key octets, or
      # whose key is not UTF-8, fails the connection.
      def test_damaged_objects_fail
        ordered = "01 0B 02000000 0C000000 00000000 06000000 01000000 61 02 01000000 62 01"

        assert_equal({ "a" => true, "b" => false }, decode(ordered))
        assert_fails { decode(ordered.sub("06000000 01", "00000000 01")) }
        assert_fails { decode("01 0B 02000000 0C000000 06000000 00000000 01000000 61 02 01000000 62 01") }
        assert_fails { decode(ordered.sub("06000000 01", "05000000 01")) }
        assert_fails { decode(ordered.sub("0C000000", "0D000000")) }
        assert_fails { decode("01 0B 01000000 06000000 00000000 01000000 FF 02") }
      end

      # Verifies: [PROTOCOL Values] a datetime's moment must be one of the
      # three and its zoned flag 0 or 1; a DECFLOAT must be in range.
      def test_damaged_scalars_fail
        assert_fails { decode("01 09 03 0000000000000000 0000 00 00") }
        assert_fails { decode("01 09 00 0000000000000000 0000 02 00") }
        assert_fails { decode("01 06 01#{"00" * 15} 01180000") }
        assert_fails { decode("01 08 01000000 FF") }
      end

      # Verifies: [PROTOCOL Values] a DECFLOAT node is read as turborel's
      # node reader reads it: rounded half to even to 34 digits, its trailing
      # zeros taken into its exponent.
      def test_decfloat_nodes_are_rounded_as_turborel_rounds_them
        node = ->(coefficient, exponent) { JsonBinary.decode(writer.u8(1).u8(6).i128(coefficient).i32(exponent).to_s) }

        assert_equal DecFloat.new(coefficient: 1, exponent: 1), node.call(10, 0)
        assert_equal DecFloat.new(coefficient: 0, exponent: 0), node.call(0, 9)
        assert_equal DecFloat.new(coefficient: (10**33) + 2, exponent: 1), node.call((10**34) + 15, 0)
        assert_equal DecFloat.new(coefficient: (10**33) + 2, exponent: 1), node.call((10**34) + 25, 0)
        assert_equal DecFloat.new(coefficient: -((10**33) + 25), exponent: 0), node.call(-((10**34) + 251), -1)
        assert_equal DecFloat.new(coefficient: 1, exponent: 35), node.call((10**35) - 1, 0)
      end

      # Verifies: [PROTOCOL JSON values] arrays and objects nest at most 128
      # deep, as turborel bounds them.
      def test_nesting_is_bounded
        deep = nil
        128.times { deep = [deep] }

        assert_equal deep, JsonBinary.decode(JsonBinary.encode(deep))
        too_deep = JsonBinary.encode(deep).sub("\x01".b, "\x01\x0A\x01\x00\x00\x00".b)
        assert_fails { JsonBinary.decode(too_deep) }
      end
    end
  end
end
