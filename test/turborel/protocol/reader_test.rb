# frozen_string_literal: true

require "test_helper"

module Turborel
  module Protocol
    # The fields a message is read by.
    class ReaderTest < Minitest::Test
      include TestSupport

      # Verifies: [PROTOCOL Values and fields] u8, u32 and u64 are read least
      # significant byte first.
      def test_unsigned_integers_are_little_endian
        fields = reader(hex("7F 01020304 0102030405060708 FFFFFFFF FFFFFFFFFFFFFFFF"))

        assert_equal 0x7F, fields.u8
        assert_equal 0x0403_0201, fields.u32
        assert_equal 0x0807_0605_0403_0201, fields.u64
        assert_equal 0xFFFF_FFFF, fields.u32
        assert_equal 0xFFFF_FFFF_FFFF_FFFF, fields.u64
        assert_predicate fields, :at_end?
      end

      # Verifies: [PROTOCOL Values and fields] i64 as u64 is the signed
      # number's bits, and i128 is 16 bytes of two's complement, least
      # significant first, at both of its limits.
      def test_signed_integers_are_twos_complement
        fields = reader(hex("FFFFFFFFFFFFFFFF #{"FF" * 15}7F #{"00" * 15}80 #{"FF" * 16} 01#{"00" * 15}"))

        assert_equal(-1, fields.i64)
        assert_equal (2**127) - 1, fields.i128
        assert_equal(-(2**127), fields.i128)
        assert_equal(-1, fields.i128)
        assert_equal 1, fields.i128
      end

      # Verifies: [PROTOCOL Values and fields] a flag is 0 or 1, and any
      # other byte fails the connection.
      def test_flag_is_zero_or_one
        fields = reader(hex("00 01 02"))

        refute fields.flag
        assert fields.flag
        assert_fails { fields.flag }
      end

      # Verifies: [PROTOCOL Values and fields] a string is its length in
      # bytes then its UTF-8, bytes their length then the bytes; a string
      # not UTF-8 fails the connection.
      def test_strings_and_bytes_follow_their_length
        fields = reader(hex("02000000 C3A9 03000000 000102 00000000 01000000 FF"))

        assert_equal "é", fields.str
        assert_equal Encoding::UTF_8, "é".encoding
        assert_equal "\x00\x01\x02".b, fields.bytes
        assert_equal "", fields.str
        assert_fails { fields.str }
      end

      # Verifies: [PROTOCOL Values and fields] a list is its count then each
      # item, strings a list of strings.
      def test_lists_are_counted
        fields = reader(hex("02000000 01000000 41 01000000 42 00000000"))

        assert_equal %w[A B], fields.strs
        assert_empty(fields.counted { fields.u8 })
      end

      # Verifies: [PROTOCOL Values and fields] a count larger than what
      # follows fails as the body runs out, reserving no memory for it.
      def test_false_count_fails_as_the_body_runs_out
        fields = reader(hex("FFFFFFFF 01"))

        assert_fails { fields.counted { fields.u8 } }
        assert_fails { reader(hex("FFFFFFFF 00")).bytes }
      end

      # Verifies: [PROTOCOL Frames] a body cut short, and bytes left over
      # after the last field, fail the connection.
      def test_body_cut_short_or_left_over_fails
        assert_fails { reader(hex("010203")).u32 }
        assert_fails { reader(hex("00")).finish.then { reader(hex("00")).finish } }
        assert_fails { reader(hex("0102")).take(3) }
        assert_equal "\x02".b, reader(hex("0102")).tap(&:u8).rest
      end

      # Verifies: [DESIGN] D1 values and types nest at most 16 deep, as
      # turborel's MAX_TYPE_NESTING bounds them; deeper fails the connection.
      def test_nesting_is_bounded
        fields = reader("")
        depth = ->(n) { n.zero? ? 0 : fields.nested { 1 + depth.call(n - 1) } }

        assert_equal Reader::MAX_NESTING, depth.call(Reader::MAX_NESTING)
        assert_fails { depth.call(Reader::MAX_NESTING + 1) }
      end

      # Verifies: [PROTOCOL Errors and notices] a malformed message fails with
      # SQLCODE -919 and SQLSTATE 08006, saying where.
      def test_corruption_is_a_connection_failure_naming_the_byte
        error = assert_fails { reader(hex("0102")).tap(&:u8).u32 }

        assert_match(/byte 1/, error.message)
        refute error.active
      end
    end
  end
end
