# frozen_string_literal: true

require "bigdecimal"

module Turborel
  module Protocol
    # A JSON value's stored form, which the protocol carries as its body
    # (value tag 25): turborel's binary tree (turborel RULES.md D89). A
    # document is a version octet, 1, then its root node; a node is a tag
    # octet and its body, integers little-endian. Offsets count from an
    # array's first element or an object's first member, and an object's
    # directory lists its members sorted by key octets, those of one key in
    # written order, while the members stay in written order.
    #
    # Encoding writes Ruby values as nodes; decoding (JsonDecoder) checks
    # the octets whole as it reads them, so damaged octets fail the
    # connection.
    #
    # @api private
    module JsonBinary
      # The format's version, the document's first octet.
      FORMAT_VERSION = 1
      # The longest stored form, 256 MiB, turborel's MAX_DOCUMENT_OCTETS.
      MAX_DOCUMENT_OCTETS = 1 << 28
      # The deepest arrays and objects nest, turborel's MAX_NESTING of JSON.
      MAX_NESTING = 128
      # The tags of the nodes (turborel RULES.md D89).
      NULL = 0
      # (see NULL)
      FALSE_NODE = 1
      # (see NULL)
      TRUE_NODE = 2
      # (see NULL)
      INTEGER = 3
      # (see NULL)
      DECIMAL = 4
      # (see NULL)
      WIDE = 5
      # (see NULL)
      DECFLOAT = 6
      # (see NULL)
      APPROXIMATE = 7
      # (see NULL)
      STRING = 8
      # (see NULL)
      DATETIME = 9
      # (see NULL)
      ARRAY = 10
      # (see NULL)
      OBJECT = 11
      # A datetime node's moment octet.
      MOMENTS = { 0 => :date, 1 => :time, 2 => :timestamp }.freeze
      # The range of a decimal node's units, an i64.
      I64_RANGE = Writer::I64_RANGE
      # The largest scale of a decimal node, a u8.
      MAX_DECIMAL_SCALE = Writer::MAX_U8
      # A word's bytes: a count, a size or an offset.
      WORD = 4
      # How a value of each class is written: the method of this module.
      ENCODERS = {
        NilClass => :null, TrueClass => :truth, FalseClass => :truth, Integer => :integer,
        BigDecimal => :big_decimal, Turborel::Decimal => :decimal, Float => :float, String => :string,
        Symbol => :string,
        Turborel::DecFloat => :decfloat, Turborel::Datetime => :datetime, Array => :array, Hash => :object
      }.freeze

      # The stored form of +value+.
      #
      # @param value [Object] a Ruby value of JSON
      # @param most [Integer] the longest form taken, 256 MiB but in tests
      # @return [String] binary
      # @raise [Error] SQLSTATE 22000 of a value no JSON item holds; 22003
      #   of a number out of range; 0A000 of one nested too deep, or a form
      #   longer than 256 MiB
      def self.encode(value, most: MAX_DOCUMENT_OCTETS)
        document = Writer.new.u8(FORMAT_VERSION)
        node(document, value, 0)
        bytes = document.to_s
        raise Error.beyond("a JSON value's stored form is longer than #{most} octets") if bytes.bytesize > most

        bytes
      end

      # The Ruby value of the stored form +bytes+.
      #
      # @param bytes [String]
      # @param most [Integer] the longest form taken, 256 MiB but in tests
      # @return [Object]
      # @raise [Error] a connection failure if the octets are damaged,
      #   nested past 128 or longer than 256 MiB (RULES.md D8)
      def self.decode(bytes, most: MAX_DOCUMENT_OCTETS)
        if bytes.bytesize > most
          raise Error.connection_failure("a JSON value's stored form is longer than #{most} octets")
        end

        JsonDecoder.new(bytes).document
      end

      # Writes +value+ as a node.
      #
      # @param writer [Writer]
      # @param value [Object]
      # @param depth [Integer]
      # @return [void]
      def self.node(writer, value, depth)
        raise Error.beyond("a JSON value's arrays and objects nest too deep") if depth > MAX_NESTING

        klass = value.class.ancestors.find { |ancestor| ENCODERS.key?(ancestor) }
        raise Error.data_exception("no JSON item holds a value of #{value.class}") unless klass

        send(ENCODERS.fetch(klass), writer, value, depth)
      end

      # @return [void]
      def self.null(writer, _value, _depth) = writer.u8(NULL)

      # @return [void]
      def self.truth(writer, value, _depth) = writer.u8(value ? TRUE_NODE : FALSE_NODE)

      # An integer, in the narrowest of its encodings.
      #
      # @return [void]
      def self.integer(writer, value, _depth) = exact(writer, value, 0)

      # @return [void]
      def self.big_decimal(writer, value, _depth)
        raise Error.out_of_range("#{value} is no JSON number") unless value.finite?

        units, scale = ValueWriter.exact_parts(value)
        exact(writer, units, scale)
      end

      # A decimal at the scale it was written with.
      #
      # @return [void]
      def self.decimal(writer, value, _depth) = exact(writer, value.units, value.scale)

      # An exact number of +units+ and +scale+, in the narrowest of its
      # three encodings.
      #
      # @return [void]
      def self.exact(writer, units, scale)
        narrow = I64_RANGE.cover?(units)
        return writer.u8(INTEGER).i64(units) if narrow && scale.zero?
        return writer.u8(DECIMAL).i64(units).u8(scale) if narrow && scale <= MAX_DECIMAL_SCALE

        writer.u8(WIDE).i128(units).u32(scale)
      end

      # @return [void]
      def self.float(writer, value, _depth) = writer.u8(APPROXIMATE).f64(value)

      # @return [void]
      def self.string(writer, value, _depth) = writer.u8(STRING).str(value.to_s)

      # @return [void]
      def self.decfloat(writer, value, _depth)
        unless Values.decfloat?(value.coefficient, value.exponent)
          raise Error.out_of_range("#{value.coefficient}E#{value.exponent} is no DECFLOAT in its one form")
        end

        writer.u8(DECFLOAT).i128(value.coefficient).i32(value.exponent)
      end

      # A datetime: moment u8, utc i64, zone minutes i16, zoned u8,
      # precision u8.
      #
      # @return [void]
      def self.datetime(writer, value, _depth)
        moment = MOMENTS.key(value.moment)
        raise Error.data_exception("#{value.moment.inspect} is no moment of a datetime") unless moment

        writer.u8(DATETIME).u8(moment).i64(value.utc).i16(value.zone).flag(value.zoned).u8(value.precision)
      end

      # An array: count u32, size u32, each element's offset u32, then
      # the elements.
      #
      # @return [void]
      def self.array(writer, value, depth)
        parts = value.map { |element| encoded(element, depth + 1) }
        container(writer, ARRAY, parts, offsets_of(parts))
      end

      # An object: count u32, size u32, each member's offset u32 in key
      # order, then the members in written order, each its key and value.
      #
      # @return [void]
      def self.object(writer, value, depth)
        keys = value.keys.map { |key| key_text(key) }
        parts = keys.zip(value.values).map { |key, member| member_bytes(key, member, depth) }
        container(writer, OBJECT, parts, directory(keys, offsets_of(parts)))
      end

      # @return [String] a member: its key, then its value's node
      def self.member_bytes(key, member, depth) = Writer.new.str(key).raw(encoded(member, depth + 1)).to_s

      # The members' offsets in key order: sorted by key octets, those of
      # one key in written order.
      #
      # @param keys [Array<String>]
      # @param offsets [Array<Integer>]
      # @return [Array<Integer>]
      def self.directory(keys, offsets)
        keys.each_index.sort_by { |index| [keys.fetch(index).b, index] }.map { |index| offsets.fetch(index) }
      end

      # @return [String] +key+, a String or a Symbol, as a member's key
      # @raise [Error] SQLSTATE 22000 of another
      def self.key_text(key)
        unless key.is_a?(String) || key.is_a?(Symbol)
          raise Error.data_exception("a JSON member's key is a #{key.class}, not a String")
        end

        key.to_s
      end

      # @return [String] +value+ as a node, binary
      def self.encoded(value, depth)
        writer = Writer.new
        node(writer, value, depth)
        writer.to_s
      end

      # @param parts [Array<String>]
      # @return [Array<Integer>] where each part begins, from the first
      def self.offsets_of(parts)
        at = 0
        parts.map { |part| at.tap { at += part.bytesize } }
      end

      # Writes a container of +tag+: its parts' count, their size, the
      # +offsets+ given, then the parts.
      #
      # @return [void]
      def self.container(writer, tag, parts, offsets)
        writer.u8(tag).u32(parts.size).u32(parts.sum(&:bytesize))
        offsets.each { |offset| writer.u32(offset) }
        parts.each { |part| writer.raw(part) }
      end
    end
  end
end
