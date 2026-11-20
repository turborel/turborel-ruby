# frozen_string_literal: true

require "bigdecimal"

module Turborel
  module Protocol
    # Writes Ruby values as the protocol's values [PROTOCOL Values], as a
    # parameter or a row of a copy: +nil+ as null; a String as a character
    # string, or a binary string if its encoding is binary; an Integer as an
    # exact number of scale 0 and a BigDecimal as one of the least scale
    # that holds it; a Float as an approximate number; +true+ and +false+
    # as truth values; an Array as an array; and each of the driver's value
    # classes as its own tag. A value of no other class can be sent.
    #
    # @api private
    module ValueWriter
      # How a value of each class is written: the method of this module.
      WRITERS = {
        NilClass => :null, String => :string, Integer => :integer, BigDecimal => :big_decimal,
        Turborel::Decimal => :decimal,
        Float => :float, TrueClass => :boolean, FalseClass => :boolean, Array => :array,
        Turborel::Datetime => :datetime, Turborel::Interval => :interval, Turborel::DecFloat => :decfloat,
        Turborel::Lob => :lob, Turborel::Row => :row, Turborel::Multiset => :multiset,
        Turborel::Structured => :structured, Turborel::Reference => :reference, Turborel::Json => :json,
        Turborel::Xml => :xml, Turborel::Uuid => :uuid, Turborel::Extension => :extension
      }.freeze

      # Writes +value+, its tag then its body.
      #
      # @param writer [Writer]
      # @param value [Object] a Ruby value
      # @param depth [Integer] how deep within arrays and rows it is
      # @return [void]
      # @raise [Error] SQLSTATE 22000 of a value of no class the driver
      #   sends; 0A000 of one nested too deep; 22003 of a number out of
      #   range
      def self.write(writer, value, depth = 0)
        raise Error.beyond("a value's arrays and rows are nested too deep") if depth > Reader::MAX_NESTING

        klass = value.class.ancestors.find { |ancestor| WRITERS.key?(ancestor) }
        raise Error.data_exception("a value of #{value.class} cannot be sent") unless klass

        send(WRITERS.fetch(klass), writer, value, depth)
      end

      # Writes +values+, a row or an Execute's values: their count, then
      # each.
      #
      # @param writer [Writer]
      # @param values [Array]
      # @param depth [Integer]
      # @return [void]
      def self.row_values(writer, values, depth = 0)
        writer.u32(values.size)
        values.each { |value| write(writer, value, depth + 1) }
      end

      # @return [void]
      def self.null(writer, _value, _depth) = writer.u8(Values::NULL)

      # @return [void]
      def self.string(writer, value, _depth)
        return writer.u8(Values::BINARY).bytes(value) if value.encoding == Encoding::BINARY

        writer.u8(Values::CHARACTER).str(value)
      end

      # @return [void]
      def self.integer(writer, value, _depth) = writer.u8(Values::EXACT).i128(value).u32(0)

      # A decimal at its own scale.
      #
      # @return [void]
      def self.decimal(writer, value, _depth) = writer.u8(Values::EXACT).i128(value.units).u32(value.scale)

      # The least scale that holds +value+, and its units at that scale.
      #
      # @return [void]
      def self.big_decimal(writer, value, _depth)
        raise Error.out_of_range("#{value} is no exact number") unless value.finite?

        units, scale = exact_parts(value)
        writer.u8(Values::EXACT).i128(units).u32(scale)
      end

      # @param value [BigDecimal] finite
      # @return [Array(Integer, Integer)] its units and scale
      def self.exact_parts(value)
        return [0, 0] if value.zero?

        sign, digits, _radix, exponent = value.split
        magnitude = Integer(digits, Values::RADIX)
        units = sign.negative? ? -magnitude : magnitude
        scale = digits.size - exponent
        return [units, scale] unless scale.negative?
        raise Error.out_of_range("#{value} does not fit an i128") if -scale > Values::I128_DIGITS

        [Integer("#{units}#{"0" * -scale}", Values::RADIX), 0]
      end

      # @return [void]
      def self.float(writer, value, _depth) = writer.u8(Values::APPROXIMATE).f64(value)

      # @return [void]
      def self.boolean(writer, value, _depth) = writer.u8(Values::BOOLEAN).flag(value)

      # @return [void]
      def self.array(writer, value, depth)
        writer.u8(Values::ARRAY)
        row_values(writer, value, depth)
      end

      # @return [void]
      def self.datetime(writer, value, _depth)
        tag = Values::MOMENTS.key(value.moment)
        raise Error.data_exception("#{value.moment.inspect} is no moment of a datetime") unless tag

        writer.u8(tag).flag(value.zoned).u8(value.precision)
        writer.u32(zone_field(value.zone)).i64(value.utc)
      end

      # @param zone [Integer] a displacement in minutes, an i16
      # @return [Integer] its bits in the low half of a u32
      # @raise [Error] SQLSTATE 22003 if it does not fit an i16
      def self.zone_field(zone)
        unless Writer::I16_RANGE.cover?(zone)
          raise Error.out_of_range("a displacement of #{zone} minutes does not fit an i16")
        end

        zone & Values::MAX_ZONE_FIELD
      end

      # @return [void]
      def self.interval(writer, value, _depth)
        writer.u8(Values::INTERVAL)
        [value.start, value.finish].each do |field|
          number = Types::FIELDS.index(field)
          raise Error.data_exception("#{field.inspect} is no field of an interval") unless number

          writer.u32(number)
        end
        writer.u32(value.leading).u32(value.fraction).i128(value.units)
      end

      # @return [void]
      def self.decfloat(writer, value, _depth)
        unless Values.decfloat?(value.coefficient, value.exponent)
          raise Error.out_of_range("#{value.coefficient}E#{value.exponent} is no DECFLOAT in its one form")
        end

        writer.u8(Values::DECFLOAT).i128(value.coefficient).i32(value.exponent)
      end

      # A large object whole, if it holds its data; else by its locator.
      #
      # @return [void]
      def self.lob(writer, value, _depth)
        kind = Values::LOB_KINDS.key(value.kind)
        raise Error.data_exception("#{value.kind.inspect} is no kind of large object") unless kind

        data = value.data
        return writer.u8(Values::LOB_WHOLE).u8(kind).bytes(lob_octets(value.kind, data)) if data

        locator(writer.u8(Values::LOB_LOCATOR).u8(kind), value)
      end

      # Writes a large object's locator u32, its octets u64 and its
      # characters u64.
      #
      # @return [void]
      def self.locator(writer, value) = writer.u32(value.locator || 0).u64(value.octets).u64(value.characters || 0)

      # @return [String] a whole large object's octets: of a character
      #   one, its UTF-8
      def self.lob_octets(kind, data) = kind == :character ? Writer.utf8(data) : data

      # @return [void]
      def self.row(writer, value, depth)
        writer.u8(Values::ROW)
        row_values(writer, value.values, depth)
      end

      # @return [void]
      def self.multiset(writer, value, depth)
        writer.u8(Values::MULTISET)
        row_values(writer, value.values, depth)
      end

      # @return [void]
      def self.structured(writer, value, depth)
        writer.u8(Values::STRUCTURED).str(value.schema).str(value.name)
        row_values(writer, value.attributes, depth)
      end

      # @return [void]
      def self.reference(writer, value, _depth) = writer.u8(Values::REFERENCE).bytes(value.octets)

      # @return [void]
      def self.json(writer, value, _depth) = writer.u8(Values::JSON).bytes(JsonBinary.encode(value.value))

      # @return [void]
      def self.xml(writer, value, _depth) = writer.u8(Values::XML).str(value.text)

      # @return [void]
      def self.uuid(writer, value, _depth)
        octets = value.octets.b
        unless octets.bytesize == Values::UUID_OCTETS
          raise Error.out_of_range("a UUID is 16 octets, not #{octets.bytesize}")
        end

        writer.u8(Values::UUID).bytes(octets)
      end

      # A plug-in's value, as it came: its type's name, its text and its
      # bytes.
      #
      # @return [void]
      def self.extension(writer, value, _depth)
        writer.u8(Values::EXTENSION).str(value.name).str(value.text).bytes(value.bytes)
      end
    end
  end
end
