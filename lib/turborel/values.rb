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

  # An XML value [PROTOCOL Values]: its serialization as CONTENT.
  Xml = Data.define(:text)

  # A UUID: its 16 octets (turborel RULES.md D184).
  Uuid = Data.define(:octets)

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
