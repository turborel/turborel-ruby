# frozen_string_literal: true

module Turborel
  module Protocol
    # Reads values [PROTOCOL Values], each its tag then its body, into Ruby
    # values, as Values describes. A tag no value has, or a body out of its
    # bounds, fails the connection.
    #
    # @api private
    module ValueReader
      # The value +reader+ reads.
      #
      # @param reader [Reader]
      # @return [Object] the Ruby value
      # @raise [Error] a connection failure if it is malformed
      def self.read(reader)
        tag = reader.u8
        method = Values::READERS.fetch(tag) { raise reader.corrupt("no value has the tag #{tag}") }
        send(method, reader, tag)
      end

      # A row's values, or an Execute's: their count, then each.
      #
      # @param reader [Reader]
      # @return [Array]
      def self.row_values(reader) = reader.counted { read(reader) }

      # @return [nil] the null value
      def self.null(_reader, _tag) = nil

      # @return [String] a character string, UTF-8
      def self.character(reader, _tag) = reader.str

      # An exact number: units i128, then scale u32. Of scale 0 an
      # Integer, else a BigDecimal, either exactly the number.
      #
      # @return [Integer, BigDecimal]
      def self.exact(reader, _tag)
        units = reader.i128
        scale = reader.u32
        scale.zero? ? units : BigDecimal("#{units}e-#{scale}")
      end

      # @return [Float] the bits of an IEEE 754 double
      def self.approximate(reader, _tag) = reader.f64

      # @return [Extension] a plug-in's value: its type's name, its text and
      #   its bytes, kept as they came
      def self.extension(reader, _tag) = Extension.new(name: reader.str, text: reader.str, bytes: reader.bytes)

      # @return [String] a binary string, binary
      def self.binary(reader, _tag) = reader.bytes

      # A date, a time or a timestamp: zoned u8, precision u8, the zone's
      # displacement in minutes as an i16's bits in a u32, then the
      # instant, microseconds of UTC, i64 as u64.
      #
      # @return [Datetime]
      def self.datetime(reader, tag)
        zoned = reader.u8 == 1
        precision = reader.u8
        zone = displacement(reader)
        Datetime.new(moment: Values::READ_MOMENTS.fetch(tag), utc: reader.i64, zone:, zoned:, precision:)
      end

      # @return [Interval] its qualifier, as the INTERVAL type writes it,
      #   then units i128
      def self.interval(reader, _tag)
        q = Types.qualifier(reader)
        Interval.new(start: q.fetch(:start), finish: q.fetch(:finish), leading: q.fetch(:leading),
                     fraction: q.fetch(:fraction), units: reader.i128)
      end

      # @return [Boolean] 0 false, 1 true; unknown comes as null
      def self.boolean(reader, _tag)
        byte = reader.u8
        Reader::FLAGS.fetch(byte) { raise reader.corrupt("#{byte} is not a truth value") }
      end

      # @return [DecFloat] coefficient i128, then exponent i32 as u32, in
      #   its one form
      def self.decfloat(reader, _tag)
        coefficient = reader.i128
        exponent = signed32(reader.u32)
        raise reader.corrupt("a DECFLOAT value is malformed") unless Values.decfloat?(coefficient, exponent)

        DecFloat.new(coefficient:, exponent:)
      end

      # @return [Array] an array's elements
      def self.array(reader, _tag) = reader.nested { row_values(reader) }

      # @return [Row] a row's fields' values
      def self.row(reader, _tag) = Row.new(values: reader.nested { row_values(reader) })

      # @return [Multiset] a multiset's elements, at most 65535
      def self.multiset(reader, _tag)
        values = reader.nested { row_values(reader) }
        if values.size > Values::MAX_MULTISET_CARDINALITY
          raise reader.corrupt("a multiset has more elements than it may")
        end

        Multiset.new(values:)
      end

      # @return [Lob] a large object whole: kind u8, then its octets,
      #   UTF-8 of a character one
      def self.lob_whole(reader, _tag)
        kind = lob_kind(reader)
        data = reader.bytes
        data = data.force_encoding(Encoding::UTF_8) if kind == :character
        raise reader.corrupt("a character large object is not UTF-8") unless data.valid_encoding?

        Lob.new(kind:, data:, locator: nil, octets: data.bytesize, characters: kind == :character ? data.size : nil)
      end

      # @return [Lob] a large object by locator: kind u8, locator u32, its
      #   octets u64, its characters u64
      def self.lob_locator(reader, _tag)
        kind = lob_kind(reader)
        Lob.new(kind:, data: nil, locator: reader.u32, octets: reader.u64, characters: reader.u64)
      end

      # @return [Structured] its most specific type's schema and name, then
      #   its attributes' values
      def self.structured(reader, _tag)
        reader.nested do
          Structured.new(schema: reader.str, name: reader.str, attributes: row_values(reader))
        end
      end

      # @return [Reference] a reference's octets
      def self.reference(reader, _tag) = Reference.new(octets: reader.bytes)

      # @return [Json] the JSON value of its stored form, D89's binary tree
      def self.json(reader, _tag) = Json.new(value: JsonBinary.decode(reader.bytes))

      # @return [Xml] its serialization as CONTENT
      def self.xml(reader, _tag) = Xml.new(text: reader.str)

      # @return [Uuid] bytes of 16 octets
      def self.uuid(reader, _tag)
        octets = reader.bytes
        unless octets.bytesize == Values::UUID_OCTETS
          raise reader.corrupt("a UUID is #{octets.bytesize} octets, not 16")
        end

        Uuid.new(octets:)
      end

      # @return [Symbol] a large object's kind
      def self.lob_kind(reader)
        byte = reader.u8
        Values::LOB_KINDS.fetch(byte) { raise reader.corrupt("#{byte} is not a kind of large object") }
      end

      # @param word [Integer] a u32
      # @return [Integer] the i32 whose bits it holds
      def self.signed32(word) = word >= Values::I32_SIGN ? word - Values::I32_BIAS : word

      # A zone's displacement in minutes: an i16's bits in the low half of
      # a u32.
      #
      # @return [Integer]
      def self.displacement(reader)
        field = reader.u32
        raise reader.corrupt("a time zone displacement is out of range") if field > Values::MAX_ZONE_FIELD

        field > Values::MAX_I16 ? field - Values::I16_BIAS : field
      end
    end
  end
end
