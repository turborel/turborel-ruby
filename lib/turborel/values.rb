# frozen_string_literal: true

module Turborel
  # A date, a time or a timestamp [PROTOCOL Values]: its +moment+
  # (+:date+, +:time+ or +:timestamp+), its instant in microseconds of UTC
  # (+utc+), its zone's displacement in minutes (+zone+), whether its type
  # is WITH TIME ZONE (+zoned+), and its seconds' fractional +precision+.
  # Without a zone, the displacement is the one the value is shown in.
  Datetime = Data.define(:moment, :utc, :zone, :zoned, :precision)

  # An interval [PROTOCOL Values]: its qualifier's +start+ and +finish+
  # fields (+:year+, +:month+, +:day+, +:hour+, +:minute+ or +:second+),
  # its +leading+ and +fraction+ precisions, and its +units+: months of a
  # year-month interval, microseconds of a day-time one.
  Interval = Data.define(:start, :finish, :leading, :fraction, :units)

  # A decimal floating point number [PROTOCOL Values]: +coefficient+
  # times ten to the +exponent+, the coefficient of at most 34 digits and
  # no trailing zero.
  DecFloat = Data.define(:coefficient, :exponent)

  # An exact number that keeps the scale it was written with [PROTOCOL JSON
  # values]: +units+ divided by ten to the +scale+, so 1.50 is units 150
  # and scale 2. A JSON value's decimal is read as one, and one is written
  # at its own scale; a BigDecimal keeps no scale.
  Decimal = Data.define(:units, :scale)

  # An exact number's forms.
  class Decimal
    # @return [BigDecimal] the number
    def to_d = BigDecimal("#{units}e-#{scale}")

    # @return [String] the number as SQL writes it, with its scale's
    #   digits after the point, as 1.50
    def to_s
      return units.to_s if scale.zero?

      digits = units.abs.to_s.rjust(scale + 1, "0").insert(-scale - 1, ".")
      units.negative? ? "-#{digits}" : digits
    end
  end

  # A large object [PROTOCOL Values]: its +kind+ (+:character+ or
  # +:binary+), and either its octets whole (+data+), or its +locator+
  # with its lengths in octets and characters. A locator lasts until its
  # transaction ends.
  Lob = Data.define(:kind, :data, :locator, :octets, :characters)

  # A row value [PROTOCOL Values]: its fields' values, in order.
  Row = Data.define(:values)

  # A multiset [PROTOCOL Values]: its elements, in no set order.
  Multiset = Data.define(:values)

  # A value of a structured type [PROTOCOL Values]: its most specific
  # type's +schema+ and +name+, and its +attributes+' values.
  Structured = Data.define(:schema, :name, :attributes)

  # A reference to a row of a typed table [PROTOCOL Values]: its octets.
  Reference = Data.define(:octets)

  # A value of the JSON type [PROTOCOL Values]: its item as Ruby values
  # (Hash, Array, String, Integer, BigDecimal, Float, DecFloat, Datetime,
  # true, false, and +nil+ for the JSON null).
  Json = Data.define(:value)

  # An XML value [PROTOCOL Values]: its serialization as CONTENT, the
  # text a parameter of an XML type is made of [CLIENT XML values].
  Xml = Data.define(:text)

  # An XML value's nodes.
  class Xml
    # Its nodes, parsed from its text.
    #
    # @return [Array<XmlNodes::Element, XmlNodes::Text, XmlNodes::Comment,
    #   XmlNodes::ProcessingInstruction>]
    # @raise [Error] SQLSTATE 2200N if it is not well-formed XML content
    def nodes = XmlNodes.parse(text)
  end

  # A UUID: its 16 octets (turborel RULES.md D184) [CLIENT UUIDs].
  Uuid = Data.define(:octets)

  # A UUID's text.
  class Uuid
    # The octets of each group of its text.
    GROUPS = [4, 2, 2, 2, 6].freeze
    # Its text's form: 32 hexadecimal digits, a hyphen allowed after each
    # group of four but the last.
    FORM = /\A(?:\h{4}-?){7}\h{4}\z/

    # The UUID +text+ writes, as turborel's CAST reads it: 32 hexadecimal
    # digits in either case, its spaces trimmed, braced or not, a hyphen
    # allowed after each group of four digits but the last.
    #
    # @param text [String]
    # @return [Uuid, nil] +nil+ if it writes none
    def self.parse(text)
      trimmed = text.gsub(/\A[[:space:]]+|[[:space:]]+\z/, "")
      trimmed = trimmed[1...-1] || "" if trimmed.start_with?("{") && trimmed.end_with?("}") && trimmed.length > 1
      new(octets: [trimmed.delete("-")].pack("H*")) if FORM.match?(trimmed)
    end

    # @return [String] its text, as 919108f7-52d1-4320-9bac-f847db4148a8
    def text
      hex = octets.unpack1("H*").to_s
      at = 0
      GROUPS.map { |n| hex[at, n * 2].tap { at += n * 2 } }.join("-")
    end
  end

  # A value of a plug-in's type [PROTOCOL Values]: its type's +name+, its
  # +text+ and its +bytes+, kept as they came so it is sent back unchanged.
  Extension = Data.define(:name, :text, :bytes)

  # A data type [PROTOCOL Data types]: its +kind+, a Symbol, and its
  # +params+, a Hash of what the kind writes after its tag.
  DataType = Data.define(:kind, :params)

  # A column of a result [PROTOCOL Composite fields]: its +name+, +nil+ if
  # unnamed, its DataType, and whether it is known +not_null+.
  Column = Data.define(:name, :type, :not_null)

  # A dynamic parameter of a prepared statement [PROTOCOL Composite
  # fields]: its DataType, and whether the server gave it CHARACTER
  # VARYING of the longest length as one the statement does not decide
  # (+varying+).
  Parameter = Data.define(:varying, :type)
end
