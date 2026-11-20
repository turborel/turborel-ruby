# frozen_string_literal: true

module Turborel
  module Protocol
    # Writes a message's fields [PROTOCOL Values and fields]: every integer
    # little-endian, a string or bytes their length then their octets, a
    # list its count then each item. A number that does not fit its field,
    # or a string that is not UTF-8, is refused before anything is sent.
    #
    # @api private
    class Writer
      # The largest a u8 holds.
      MAX_U8 = 0xFF
      # The largest a u32 holds.
      MAX_U32 = 0xFFFF_FFFF
      # The largest a u64 holds.
      MAX_U64 = 0xFFFF_FFFF_FFFF_FFFF
      # The range an i16 holds.
      I16_RANGE = -0x8000..0x7FFF
      # The range an i32 holds.
      I32_RANGE = -0x8000_0000..0x7FFF_FFFF
      # The range an i64 holds.
      I64_RANGE = -0x8000_0000_0000_0000..0x7FFF_FFFF_FFFF_FFFF
      # The range an i128 holds.
      I128_RANGE = -0x8000_0000_0000_0000_0000_0000_0000_0000..0x7FFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF
      # The low half of an i128.
      LOW_MASK = MAX_U64
      # The bits the low half of an i128 takes.
      HALF_BITS = 64
      # Array#pack's directives of the fields, little-endian.
      U8 = "C"
      # (see U8)
      I16 = "s<"
      # (see U8)
      U32 = "V"
      # (see U8)
      U64 = "Q<"
      # (see U8)
      I64 = "q<"
      # (see U8)
      F64 = "E"

      # An empty buffer.
      def initialize
        @out = +"".b
      end

      # @return [String] what was written, binary
      def to_s = @out

      # @param value [Integer] a byte
      # @return [self]
      def u8(value) = put(checked(value, 0..MAX_U8, "u8"), U8)

      # @param value [Integer] four bytes, unsigned
      # @return [self]
      def u32(value) = put(checked(value, 0..MAX_U32, "u32"), U32)

      # @param value [Integer] eight bytes, unsigned
      # @return [self]
      def u64(value) = put(checked(value, 0..MAX_U64, "u64"), U64)

      # @param value [Integer] two bytes, two's complement
      # @return [self]
      def i16(value) = put(checked(value, I16_RANGE, "i16"), I16)

      # @param value [Integer] four bytes, the signed number's bits in a
      #   u32
      # @return [self]
      def i32(value) = u32(checked(value, I32_RANGE, "i32") & MAX_U32)

      # @param value [Integer] eight bytes, two's complement
      # @return [self]
      def i64(value) = put(checked(value, I64_RANGE, "i64"), I64)

      # @param value [Integer] sixteen bytes, two's complement, least
      #   significant first
      # @return [self]
      def i128(value)
        checked(value, I128_RANGE, "i128")
        put(value & LOW_MASK, U64)
        put(value >> HALF_BITS, I64)
      end

      # @param value [Float] the IEEE 754 double's bits
      # @return [self]
      def f64(value) = put(value, F64)

      # @param value [String] octets, after their u32 length
      # @return [self]
      def bytes(value)
        octets = value.b
        u32(checked(octets.bytesize, 0..MAX_U32, "length"))
        raw(octets)
      end

      # @param value [String] a string, its UTF-8 after its u32 length
      # @return [self]
      # @raise [Error] if it cannot be written as UTF-8
      def str(value) = bytes(Writer.utf8(value))

      # @param value [Boolean] a flag, 0 or 1
      # @return [self]
      def flag(value) = u8(value ? 1 : 0)

      # @param values [Array<String>] a list of strings
      # @return [self]
      def strs(values)
        u32(values.size)
        values.each { |value| str(value) }
        self
      end

      # @param octets [String] bytes with no length before them
      # @return [self]
      def raw(octets)
        @out << octets.b
        self
      end

      # +value+ as UTF-8.
      #
      # @param value [String]
      # @return [String]
      # @raise [Error] if it cannot be written as UTF-8 (SQLSTATE 22021)
      def self.utf8(value)
        text = value.encode(Encoding::UTF_8)
        raise Error.not_in_repertoire("a string is not valid #{value.encoding}") unless text.valid_encoding?

        text
      rescue EncodingError => e
        raise Error.not_in_repertoire("a string cannot be written as UTF-8: #{e.message}")
      end

      private

      # Appends +value+ packed by +directive+.
      def put(value, directive)
        @out << [value].pack(directive)
        self
      end

      # +value+, if +range+ covers it; refused with SQLSTATE 22003 if not.
      def checked(value, range, field)
        raise Error.out_of_range("#{value} does not fit a #{field}") unless range.cover?(value)

        value
      end
    end
  end
end
