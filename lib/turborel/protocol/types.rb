# frozen_string_literal: true

module Turborel
  module Protocol
    # Data types as the server writes them [PROTOCOL Data types]: a tag,
    # then what its kind writes after it, read into a DataType. A distinct
    # type comes as its source type. The client never sends a type.
    #
    # @api private
    module Types
      # The kind of each type tag [PROTOCOL Data types], UUID's 27 among
      # them (turborel RULES.md D184).
      KINDS = {
        1 => :character, 2 => :exact, 3 => :approximate, 4 => :extension, 5 => :varying,
        6 => :binary, 7 => :varbinary, 8 => :date, 9 => :time, 10 => :time_zoned,
        11 => :timestamp, 12 => :timestamp_zoned, 13 => :interval, 14 => :boolean,
        15 => :decfloat, 16 => :array, 17 => :row, 18 => :clob, 19 => :blob,
        22 => :multiset, 23 => :structured, 24 => :reference, 25 => :json, 26 => :xml,
        27 => :uuid
      }.freeze
      # How each kind's parameters are read: the method of this module.
      PARAMS = {
        character: :length_units, varying: :length_units, exact: :precision_scale,
        approximate: :precision, decfloat: :precision, date: :precision, time: :precision,
        time_zoned: :precision, timestamp: :precision, timestamp_zoned: :precision,
        binary: :length, varbinary: :length, clob: :lob_length, blob: :lob_length,
        interval: :qualifier, boolean: :nothing, json: :nothing, uuid: :nothing,
        array: :array, multiset: :multiset, row: :row, structured: :structured,
        reference: :reference, xml: :xml, extension: :extension
      }.freeze
      # A character type's units [PROTOCOL Data types].
      UNITS = { 0 => :characters, 1 => :octets }.freeze
      # An interval's fields, by their numbers [PROTOCOL Data types].
      FIELDS = %i[year month day hour minute second].freeze
      # An XML type's primary modifier [PROTOCOL Data types].
      XML_PRIMARY = { 0 => :document, 1 => :content, 2 => :sequence }.freeze
      # An XML type's secondary modifier [PROTOCOL Data types].
      XML_SECONDARY = { 0 => :untyped, 1 => :any, 2 => :xmlschema }.freeze
      # The largest maximum cardinality of an array type, turborel's
      # MAX_ARRAY_CARDINALITY.
      MAX_ARRAY_CARDINALITY = 65_535
      # The most parameters a plug-in's type has, turborel's MAX_PARAMS.
      MAX_EXTENSION_PARAMS = 2
      # The one parameter value a plug-in's type never has: u32's largest,
      # which marks a parameter absent in turborel.
      ABSENT_PARAM = 0xFFFF_FFFF

      # The data type +reader+ reads.
      #
      # @param reader [Reader]
      # @return [DataType]
      # @raise [Error] a connection failure if it is malformed
      def self.read(reader)
        tag = reader.u8
        kind = KINDS.fetch(tag) { raise reader.corrupt("no data type has the tag #{tag}") }
        DataType.new(kind:, params: send(PARAMS.fetch(kind), reader))
      end

      # The tag of +kind+.
      #
      # @param kind [Symbol]
      # @return [Integer]
      def self.tag(kind) = KINDS.key(kind) || 0

      # @param _reader [Reader]
      # @return [Hash] no parameters
      def self.nothing(_reader) = {}

      # @param reader [Reader]
      # @return [Hash] a length u32 and units u8
      def self.length_units(reader) = { length: reader.u32, units: units(reader) }

      # @param reader [Reader]
      # @return [Hash] a precision u32 and a scale u32
      def self.precision_scale(reader) = { precision: reader.u32, scale: reader.u32 }

      # @param reader [Reader]
      # @return [Hash] a precision u32
      def self.precision(reader) = { precision: reader.u32 }

      # @param reader [Reader]
      # @return [Hash] a length u32
      def self.length(reader) = { length: reader.u32 }

      # @param reader [Reader]
      # @return [Hash] a length u64 and units u8
      def self.lob_length(reader) = { length: reader.u64, units: units(reader) }

      # An interval's qualifier: start field, end field, leading
      # precision, fractional precision, each u32.
      #
      # @param reader [Reader]
      # @return [Hash]
      def self.qualifier(reader)
        start = field(reader)
        { start:, finish: field(reader), leading: reader.u32, fraction: reader.u32 }
      end

      # @param reader [Reader]
      # @return [Hash] a maximum cardinality, 1 to 65535, then the element
      #   type
      def self.array(reader)
        reader.nested do
          max = reader.u32
          unless max.between?(1, MAX_ARRAY_CARDINALITY)
            raise reader.corrupt("an array type's cardinality #{max} is out of range")
          end

          { max:, element: read(reader) }
        end
      end

      # @param reader [Reader]
      # @return [Hash] the element type
      def self.multiset(reader) = reader.nested { { element: read(reader) } }

      # @param reader [Reader]
      # @return [Hash] one or more fields, each a name and a type
      def self.row(reader)
        reader.nested do
          fields = reader.counted { [reader.str, read(reader)] }
          raise reader.corrupt("a row type has no fields") if fields.empty?

          { fields: }
        end
      end

      # @param reader [Reader]
      # @return [Hash] a structured type's schema and name, and its proper
      #   supertypes' schemas and names
      def self.structured(reader)
        { schema: reader.str, name: reader.str, supertypes: reader.counted { [reader.str, reader.str] } }
      end

      # @param reader [Reader]
      # @return [Hash] the referenced type's names, then its scope's schema
      #   and name, +nil+ if unscoped
      def self.reference(reader)
        names = structured(reader)
        scoped = reader.u8
        raise reader.corrupt("a reference type's scope flag is #{scoped}") unless scoped.between?(0, 1)

        names.merge(scope: scoped.zero? ? nil : [reader.str, reader.str])
      end

      # An XML type's modifiers, and of XMLSCHEMA what it names.
      #
      # @param reader [Reader]
      # @return [Hash]
      def self.xml(reader)
        primary = modifier(reader, XML_PRIMARY, "primary")
        secondary = modifier(reader, XML_SECONDARY, "secondary")
        raise reader.corrupt("an XML type of SEQUENCE is typed") if primary == :sequence && secondary != :untyped

        { primary:, secondary:, schema: secondary == :xmlschema ? xml_schema(reader) : nil }
      end

      # A plug-in's type: its name, and at most two parameters, none u32's
      # largest.
      #
      # @param reader [Reader]
      # @return [Hash]
      def self.extension(reader)
        name = reader.str
        params = reader.counted { reader.u32 }
        if params.size > MAX_EXTENSION_PARAMS || params.include?(ABSENT_PARAM)
          raise reader.corrupt("a type has too many parameters, or an absent one")
        end

        { name:, params: }
      end

      # @param reader [Reader]
      # @return [Symbol] a character type's units
      def self.units(reader)
        unit = reader.u8
        UNITS.fetch(unit) { raise Error.corrupt_value("a type's units are #{unit}") }
      end

      # @param reader [Reader]
      # @return [Symbol] an interval's field, by its number
      def self.field(reader)
        number = reader.u32
        # Compared before it indexes, as Array#fetch takes a C long, which
        # on Windows does not hold every u32.
        raise reader.corrupt("an interval's field #{number} is out of range") unless number < FIELDS.size

        FIELDS.fetch(number)
      end

      # @param reader [Reader]
      # @param modifiers [Hash{Integer => Symbol}]
      # @param which [String]
      # @return [Symbol] an XML type's modifier
      def self.modifier(reader, modifiers, which)
        byte = reader.u8
        modifiers.fetch(byte) { raise reader.corrupt("an XML type's #{which} modifier is #{byte}") }
      end

      # What an XML type of XMLSCHEMA names: the schema's schema and name,
      # then its namespace and its element, each 0 for none or 1 and a
      # string.
      #
      # @param reader [Reader]
      # @return [Hash]
      def self.xml_schema(reader)
        { schema: reader.str, name: reader.str, namespace: optional(reader), element: optional(reader) }
      end

      # @param reader [Reader]
      # @return [String, nil] 0 for none, or 1 and a string
      def self.optional(reader)
        present = reader.flag
        present ? reader.str : nil
      end
    end
  end
end
