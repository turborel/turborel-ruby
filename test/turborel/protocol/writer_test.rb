# frozen_string_literal: true

require "test_helper"

module Turborel
  module Protocol
    # The fields a message is written by.
    class WriterTest < Minitest::Test
      include TestSupport

      # Verifies: [PROTOCOL Values and fields] integers are written least
      # significant byte first, i32 and i64 as their bits, i128 as 16 bytes
      # of two's complement.
      def test_integers_are_little_endian
        bytes = writer.u8(0x7F).u32(0x0403_0201).u64(0x0807_0605_0403_0201).i32(-1).i64(-2).i16(-3).to_s

        assert_equal hex("7F 01020304 0102030405060708 FFFFFFFF FEFFFFFFFFFFFFFF FDFF"), bytes
        assert_equal hex("#{"FF" * 15}7F #{"00" * 15}80"), writer.i128((2**127) - 1).i128(-(2**127)).to_s
      end

      # Verifies: [PROTOCOL Values and fields] strings, bytes, flags and
      # lists are written as they are read.
      def test_strings_bytes_flags_and_lists
        bytes = writer.str("é").bytes("\x00".b).flag(true).flag(false).strs(%w[A]).raw("Z").to_s

        assert_equal hex("02000000 C3A9 01000000 00 01 00 01000000 01000000 41 5A"), bytes
        assert_equal Encoding::BINARY, bytes.encoding
      end

      # Verifies: [DESIGN] D8 a number that does not fit its field is refused
      # with SQLSTATE 22003, never truncated.
      def test_numbers_out_of_their_field_are_refused
        assert_fails(OUT_OF_RANGE) { writer.u8(256) }
        assert_fails(OUT_OF_RANGE) { writer.u32(-1) }
        assert_fails(OUT_OF_RANGE) { writer.u64(2**64) }
        assert_fails(OUT_OF_RANGE) { writer.i32(2**31) }
        assert_fails(OUT_OF_RANGE) { writer.i64(-(2**63) - 1) }
        assert_fails(OUT_OF_RANGE) { writer.i128(2**127) }
        assert_fails(OUT_OF_RANGE) { writer.i16(2**15) }
      end

      # Verifies: [PROTOCOL Values and fields] a string is written as UTF-8,
      # from another encoding too; one that is not valid is refused with
      # SQLSTATE 22021.
      def test_strings_are_written_as_utf8
        latin = "\xE9".dup.force_encoding(Encoding::ISO_8859_1)

        assert_equal hex("02000000 C3A9"), writer.str(latin).to_s
        repertoire = [Error::DATA_EXCEPTION_SQLCODE, Error::NOT_IN_REPERTOIRE_SQLSTATE]
        assert_fails(repertoire) { writer.str("\xFF".dup.force_encoding(Encoding::UTF_8)) }
        assert_fails(repertoire) { writer.str("\x81".dup.force_encoding(Encoding::Shift_JIS)) }
      end
    end
  end
end
