# frozen_string_literal: true

require "bigdecimal"

module Turborel
  module Protocol
    # Reads a JSON value's stored form (JsonBinary) into Ruby values,
    # checking it whole as turborel's binary::validate does: every node
    # within the document, each string UTF-8, each element where its
    # offset says and filling its array's size, each object's members
    # filling its size and its directory listing each once, sorted by key
    # octets then by place. An object becomes a Hash in written order; of
    # members of one key, the first written is kept, as a member accessor
    # takes it.
    #
    # @api private
    class JsonDecoder
      # The bytes of a word: a count, a size, an offset or a length.
      WORD = JsonBinary::WORD
      # The bytes of an i64, a u64 or an f64.
      LONG = 8
      # The bytes of an i128.
      I128_BYTES = 16
      # A container's head: its count and its size.
      HEAD_BYTES = 2 * WORD
      # The bytes of a decimal node's body: units i64, scale u8.
      DECIMAL_BYTES = LONG + 1
      # The bytes of a wide decimal's or a DECFLOAT's body: an i128, then
      # a u32 or an i32.
      WIDE_BYTES = I128_BYTES + WORD
      # Where a datetime's fields begin in its body, and the bytes of it:
      # moment u8, utc i64, zone i16, zoned u8, precision u8.
      UTC_AT = 1
      # (see UTC_AT)
      ZONE_AT = UTC_AT + LONG
      # (see UTC_AT)
      ZONED_AT = ZONE_AT + 2
      # (see UTC_AT)
      PRECISION_AT = ZONED_AT + 1
      # (see UTC_AT)
      DATETIME_BYTES = PRECISION_AT + 1
      # The bits of an i128's low half.
      HALF_BITS = 64
      # String#unpack1's directives, little-endian.
      I64 = "q<"
      # (see I64)
      U64 = "Q<"
      # (see I64)
      U32 = "V"
      # (see I64)
      I16 = "s<"
      # (see I64)
      F64 = "E"
      # The bytes of an i16.
      I16_BYTES = 2
      # The values of the nodes with no body.
      CONSTANTS = { JsonBinary::NULL => nil, JsonBinary::FALSE_NODE => false, JsonBinary::TRUE_NODE => true }.freeze
      # How each tag's node is read: the method of this class.
      READERS = {
        JsonBinary::INTEGER => :integer, JsonBinary::DECIMAL => :decimal, JsonBinary::WIDE => :wide,
        JsonBinary::DECFLOAT => :decfloat, JsonBinary::APPROXIMATE => :approximate,
        JsonBinary::STRING => :string, JsonBinary::DATETIME => :datetime,
        JsonBinary::ARRAY => :array, JsonBinary::OBJECT => :object
      }.freeze

      # A decoder of the stored form +bytes+.
      #
      # @param bytes [String]
      def initialize(bytes)
        @bytes = bytes.b
      end

      # The document's root, which must be all of it after its version.
      #
      # @return [Object]
      # @raise [Error] a connection failure if the octets are damaged
      def document
        unless @bytes.getbyte(0) == JsonBinary::FORMAT_VERSION && @bytes.bytesize > 1
          raise corrupt("it does not begin with its format's version")
        end

        value, length = node(1, 0)
        raise corrupt("octets follow its root") unless length + 1 == @bytes.bytesize

        value
      end

      private

      # The value of the node at +at+, and the bytes it takes.
      def node(at, depth)
        raise corrupt("arrays and objects nest too deep") if depth > JsonBinary::MAX_NESTING

        tag = byte(at)
        return [CONSTANTS.fetch(tag), 1] if CONSTANTS.key?(tag)

        reader = READERS.fetch(tag) { raise corrupt("a node's tag #{tag} is no kind's") }
        value, body = send(reader, at + 1, depth)
        [value, body + 1]
      end

      # Node 3: an i64.
      def integer(at, _depth) = [unpack(at, LONG, I64), LONG]

      # Node 7: an f64's bits.
      def approximate(at, _depth) = [unpack(at, LONG, F64), LONG]

      # Node 4: units i64, scale u8.
      def decimal(at, _depth)
        units = unpack(at, LONG, I64)
        [exact(units, byte(at + LONG)), DECIMAL_BYTES]
      end

      # Node 5: units i128, scale u32.
      def wide(at, _depth) = [exact(i128(at), word(at + I128_BYTES)), WIDE_BYTES]

      # Node 6: coefficient i128, exponent i32, in its one form.
      def decfloat(at, _depth)
        coefficient = i128(at)
        exponent = ValueReader.signed32(word(at + I128_BYTES))
        # A node's DECFLOAT is made as turborel's node reader makes it,
        # rounded to 34 digits, and refused only out of range.
        value = Values.rounded_decfloat(coefficient, exponent)
        raise corrupt("a DECFLOAT is out of range") unless value

        [value, WIDE_BYTES]
      end

      # Node 8: octets u32, then UTF-8.
      def string(at, _depth)
        text, taken = text_at(at)
        [text, taken]
      end

      # Node 9: moment u8, UTC i64, zone i16, zoned u8, precision u8.
      def datetime(at, _depth)
        moment = JsonBinary::MOMENTS.fetch(byte(at)) { raise corrupt("a datetime's moment is no moment") }
        zoned = Reader::FLAGS.fetch(byte(at + ZONED_AT)) { raise corrupt("a datetime's zoned flag is neither 0 nor 1") }
        value = Datetime.new(moment:, utc: unpack(at + UTC_AT, LONG, I64), zone: unpack(at + ZONE_AT, I16_BYTES, I16),
                             zoned:, precision: byte(at + PRECISION_AT))
        [value, DATETIME_BYTES]
      end

      # An array: each element where its offset says, one after another,
      # filling its size.
      def array(at, depth)
        count, size, first = head(at)
        expected = 0
        values = Array.new(count) do |index|
          raise corrupt("an element's offset is not where it is") unless offset(at, index) == expected

          value, taken = node(first + expected, depth + 1)
          expected += taken
          value
        end
        raise corrupt("an array's size is not its elements'") unless expected == size

        [values, first - at + size]
      end

      # An object: its members one after another, filling its size, and
      # its directory listing each once, sorted.
      def object(at, depth)
        count, size, first = head(at)
        members, starts, length = members(first, count, depth)
        raise corrupt("an object's size is not its members'") unless length == size

        check_directory(at, first, starts)
        [first_of_each_key(members), first - at + size]
      end

      # The members as a Hash, in written order, the first written of each
      # key kept.
      def first_of_each_key(members)
        object = {} #: Hash[String, json]
        members.each { |key, value| object[key] = value unless object.key?(key) }
        object
      end

      # The members from +first+, each key and value, where each begins,
      # and the bytes they take.
      def members(first, count, depth)
        at = 0
        starts = [] #: Array[Integer]
        members = Array.new(count) do
          starts << at
          key, key_bytes = text_at(first + at)
          value, taken = node(first + at + key_bytes, depth + 1)
          at += key_bytes + taken
          [key, value] #: [String, json]
        end
        [members, starts, at]
      end

      # That an object's directory names each member once, sorted by key
      # octets, then by place.
      def check_directory(at, first, starts)
        known = starts.to_h { |start| [start, true] }
        entries = starts.each_index.map { |index| entry(at, first, known, index) }
        sorted = entries.each_cons(2).all? { |before, after| (before <=> after)&.negative? }
        raise corrupt("an object's key directory is not sorted") unless sorted
      end

      # The key octets and offset of a directory's entry +index+, which
      # must name the start of a member.
      def entry(at, first, known, index)
        offset = offset(at, index)
        raise corrupt("an object's key directory names no member") unless known.key?(offset)

        [text_at(first + offset).first.b, offset]
      end

      # The offset of a container's part +index+, from its directory.
      def offset(at, index) = word(at + HEAD_BYTES + (index * WORD))

      # A container's count and size, and where its first part begins,
      # its offsets within the document.
      def head(at)
        count = word(at)
        size = word(at + WORD)
        first = at + HEAD_BYTES + (count * WORD)
        slice(at, HEAD_BYTES + (count * WORD) + size)
        [count, size, first]
      end

      # The string whose length is at +at+, and the bytes it takes.
      def text_at(at)
        length = word(at)
        text = slice(at + WORD, length).force_encoding(Encoding::UTF_8)
        raise corrupt("a string is not UTF-8") unless text.valid_encoding?

        [text, WORD + length]
      end

      # The exact number of +units+ and +scale+: an Integer of scale 0.
      def exact(units, scale) = scale.zero? ? units : Decimal.new(units:, scale:)

      # The i128 at +at+.
      def i128(at) = (unpack(at + LONG, LONG, I64) << HALF_BITS) | unpack(at, LONG, U64)

      # The u32 at +at+.
      def word(at) = unpack(at, WORD, U32)

      # The u8 at +at+.
      def byte(at) = slice(at, 1).getbyte(0) || 0

      # The number of +count+ bytes at +at+, read by +directive+.
      def unpack(at, count, directive)
        # String#unpack1's type depends on its directive, which only run
        # time reads; each directive here gives an Integer or a Float.
        _ = slice(at, count).unpack1(directive)
      end

      # The +count+ bytes at +at+, which must be within the document.
      def slice(at, count)
        raise corrupt("a node runs past its document") if at + count > @bytes.bytesize

        @bytes.byteslice(at, count) || "".b
      end

      # The connection failure of damaged octets.
      def corrupt(why) = Error.connection_failure("a JSON value received is damaged: #{why}")
    end
  end
end
