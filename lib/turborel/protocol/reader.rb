# frozen_string_literal: true

module Turborel
  module Protocol
    # Reads a message's fields front to back [PROTOCOL Values and fields]:
    # every integer little-endian, a string or bytes their length then their
    # octets, a list its count then each item. What it reads is checked
    # against what remains before it is taken, so a count or a length
    # larger than what follows fails as the body runs out and never makes
    # the reader reserve memory. Any malformed field fails the connection
    # (SQLCODE -919, SQLSTATE 08006).
    #
    # @api private
    class Reader
      # The deepest arrays, rows, multisets and structured values nest,
      # of a value or a type, as turborel's MAX_TYPE_NESTING bounds them.
      MAX_NESTING = 16
      # The bytes of the integer fields.
      U8_BYTES = 1
      # (see U8_BYTES)
      U32_BYTES = 4
      # (see U8_BYTES)
      U64_BYTES = 8
      # The bits the low half of an i128 takes.
      HALF_BITS = 64
      # String#unpack1's directives of the integer fields, little-endian.
      U32 = "V"
      # (see U32)
      U64 = "Q<"
      # (see U32)
      I64 = "q<"
      # (see U32)
      F64 = "E"
      # A flag's two bytes.
      FLAGS = { 0 => false, 1 => true }.freeze

      # A reader of +bytes+, which hold a +what+, as "reply", for messages.
      #
      # @param bytes [String] the octets to read
      # @param what [String] what they hold
      def initialize(bytes, what)
        @bytes = bytes.b
        @what = what
        @at = 0
        @depth = 0
      end

      # @return [Boolean] whether every byte has been read
      def at_end? = @at >= @bytes.bytesize

      # The next +count+ bytes.
      #
      # @param count [Integer] how many
      # @return [String] binary
      # @raise [Error] if fewer are left
      def take(count)
        raise corrupt("it ends too soon") if count > @bytes.bytesize - @at

        taken = @bytes.byteslice(@at, count) || "".b
        @at += count
        taken
      end

      # @return [String] every byte left, all taken
      def rest = take(@bytes.bytesize - @at)

      # @return [Integer] a byte
      def u8 = take(U8_BYTES).getbyte(0) || 0

      # @return [Integer] four bytes, unsigned
      def u32 = unpacked(U32_BYTES, U32)

      # @return [Integer] eight bytes, unsigned
      def u64 = unpacked(U64_BYTES, U64)

      # @return [Integer] eight bytes, two's complement
      def i64 = unpacked(U64_BYTES, I64)

      # @return [Integer] sixteen bytes, two's complement, least
      #   significant first
      def i128
        low = u64
        (i64 << HALF_BITS) | low
      end

      # @return [Float] the IEEE 754 double of eight bytes, NaN and -0.0
      #   as they were
      def f64
        # String#unpack1's type depends on its directive, which only run
        # time reads; F64 gives a Float.
        _ = take(U64_BYTES).unpack1(F64)
      end

      # @return [String] bytes after their u32 length, binary
      def bytes = take(u32)

      # @return [String] a string after its u32 length, UTF-8
      # @raise [Error] if it is not UTF-8
      def str
        text = bytes.force_encoding(Encoding::UTF_8)
        raise corrupt("a string is not UTF-8") unless text.valid_encoding?

        text
      end

      # @return [Boolean] a flag
      # @raise [Error] if its byte is neither 0 nor 1
      def flag
        byte = u8
        FLAGS.fetch(byte) { raise corrupt("a flag is #{byte}, neither 0 nor 1") }
      end

      # @return [Array<String>] a list of strings
      def strs = counted { str }

      # The items of a list, each read by the block, after their count.
      # Nothing is reserved for the count: what is held grows only with
      # the items read.
      #
      # @yieldreturn [Object] an item
      # @return [Array]
      def counted
        items = [] #: Array[untyped]
        u32.times { items << yield }
        items
      end

      # What the block reads of a part nested within what it reads: an
      # array's element, a row's field, a multiset's element or a
      # structured value's attribute.
      #
      # @yieldreturn [Object] the part
      # @return [Object] the part
      # @raise [Error] if parts nest deeper than MAX_NESTING
      def nested
        raise corrupt("its arrays and rows are nested too deep") if @depth >= MAX_NESTING

        @depth += 1
        part = yield
        @depth -= 1
        part
      end

      # @raise [Error] if any byte is left: bytes left over after the last
      #   field fail the connection [PROTOCOL Frames]
      # @return [void]
      def finish
        raise corrupt("bytes are left over") unless at_end?
      end

      # The connection failure of a malformed +what+, at the current byte.
      #
      # @param why [String] what is wrong
      # @return [Error]
      def corrupt(why)
        Error.connection_failure("a #{@what} received is malformed at byte #{@at}: #{why}")
      end

      private

      # The integer of +count+ bytes, read by +directive+.
      def unpacked(count, directive)
        # String#unpack1's type depends on its directive, which only run
        # time reads; each integer directive gives an Integer.
        _ = take(count).unpack1(directive)
      end
    end
  end
end
