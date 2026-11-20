# frozen_string_literal: true

require "bigdecimal"

module Turborel
  # Values written as text, as turborel shows them, each type's Display
  # (src/value.rs and the modules of each type): what an export as CSV
  # writes of each value [CLIENT Copying and exporting], and what a value
  # nested in another is written as, its literal.
  module Text
    # Microseconds in a second, a minute and a day.
    MICROS = { second: 1_000_000, minute: 60_000_000, day: 86_400_000_000 }.freeze
    # The units of each interval field: months of YEAR and MONTH,
    # microseconds of the others.
    FIELD_UNITS = { year: 12, month: 1, day: 86_400_000_000, hour: 3_600_000_000, minute: 60_000_000, second: 1 }.freeze
    # An interval's fields in order.
    FIELDS = FIELD_UNITS.keys.freeze
    # Each interval field's place among them.
    RANKS = FIELDS.each_with_index.to_h.freeze
    # The separator before each interval field but the leading one.
    SEPARATORS = { month: "-", hour: " ", year: ":", day: ":", minute: ":", second: ":" }.freeze
    # The largest scale an exact number is written out to, turborel's
    # MAX_EXACT_PRECISION; a larger one is written as a power of ten.
    MAX_EXACT_PRECISION = 38
    # The adjusted exponents of a DECFLOAT written plain.
    DECFLOAT_PLAIN = (-6...34)
    # The days from 0000-03-01, a 400-year era's start, to 0001-01-01.
    ERA_SHIFT = 306
    # How a value of each class is shown: the method of this module.
    SHOWN = {
      NilClass => :null, String => :string, Integer => :exact, BigDecimal => :exact, Float => :approximate,
      TrueClass => :truth, FalseClass => :truth, Decimal => :own, DecFloat => :decfloat, Datetime => :datetime,
      Interval => :interval, Lob => :lob, Turborel::Json => :json, Xml => :own_text, Extension => :own_text,
      Uuid => :own_text
    }.freeze
    # How a value of each class is written as a literal, where it is not
    # as it is shown: the method of this module.
    LITERALS = {
      NilClass => :null, String => :string_literal, Array => :array_literal, Datetime => :datetime_literal,
      Interval => :interval_literal, DecFloat => :decfloat_literal, Row => :row_literal,
      Multiset => :multiset_literal, Structured => :structured_literal, Reference => :reference_literal,
      Lob => :lob_literal, Turborel::Json => :json_literal, Uuid => :uuid_literal, Xml => :xml_literal
    }.freeze

    # +value+ as turborel shows it; +nil+ as NULL. +type+, the DataType of
    # its column, gives an exact number its scale, as BigDecimal keeps
    # none.
    #
    # @param value [Object] a value as the driver reads it
    # @param type [DataType, nil]
    # @return [String]
    def self.of(value, type = nil)
      shown = SHOWN.find { |klass, _| value.is_a?(klass) }&.last
      shown ? send(shown, value, type) : literal(value, type)
    end

    # +value+ as an SQL literal: what a value nested in an array, row,
    # multiset or structured value is written as.
    #
    # @param value [Object]
    # @param type [DataType, nil]
    # @return [String]
    def self.literal(value, type = nil)
      written = LITERALS.find { |klass, _| value.is_a?(klass) }&.last
      written ? send(written, value, type) : of(value, type)
    end

    class << self
      # The null value, as NULL.
      #
      # @api private
      def null(_value, _type) = "NULL"

      # A character string as it is, a binary one in hexadecimal.
      #
      # @api private
      def string(value, _type) = value.encoding == Encoding::BINARY ? hex(value) : value

      # A truth value, as TRUE or FALSE.
      #
      # @api private
      def truth(value, _type) = value ? "TRUE" : "FALSE"

      # A value whose own to_s is its text.
      #
      # @api private
      def own(value, _type) = value.to_s

      # A value whose own text is its text.
      #
      # @api private
      def own_text(value, _type) = value.text

      # A JSON value, as its JSON text.
      #
      # @api private
      def json(value, _type) = Text::Json.shown(value.value)

      # An exact number with the scale of +type+, if it is an exact one,
      # or else the least that holds it.
      #
      # @api private
      def exact(value, type)
        units, least = Protocol::ValueWriter.exact_parts(BigDecimal(value))
        column = type && type.kind == :exact ? Integer(type.params[:scale]) : least
        scale = [column, least].max
        scaled = units * Integer(10**(scale - least))
        scale > MAX_EXACT_PRECISION ? "#{scaled}E-#{scale}" : Decimal.new(units: scaled, scale:).to_s
      end

      # An approximate number as Rust's {:E} writes it: the shortest digits
      # that read back as it, one before the point, then E and the
      # exponent.
      #
      # @api private
      def approximate(value, _type = nil)
        return "NaN" if value.nan?
        return value.positive? ? "inf" : "-inf" if value.infinite?

        sign = (1.0 / value).negative? ? "-" : ""
        return "#{sign}0E0" if value.zero?

        digits, exponent = shortest(value.abs)
        "#{sign}#{scientific(digits)}E#{exponent}"
      end

      # +digits+ with a point after the first, if there are more.
      #
      # @api private
      def scientific(digits) = digits.size > 1 ? "#{digits[0]}.#{digits[1..]}" : digits

      # The shortest digits of +value+, positive, with no zero at either
      # end, and the exponent of the first.
      #
      # @api private
      def shortest(value)
        mantissa, power = value.to_s.split("e")
        whole, fraction = mantissa.to_s.split(".")
        digits = "#{whole}#{fraction}"
        significant = digits.sub(/\A0+/, "")
        exponent = Integer(power || "0", 10) + whole.to_s.size - 1 - (digits.size - significant.size)
        [significant.sub(/0+\z/, ""), exponent]
      end

      # A DECFLOAT: plain where its adjusted exponent is from -6 to 33,
      # else its digits, one before the point, and E and the exponent.
      #
      # @api private
      def decfloat(value, _type = nil)
        digits = value.coefficient.abs.to_s
        adjusted = value.exponent + digits.size - 1
        return numeral(value.coefficient, value.exponent) if value.coefficient.zero? || DECFLOAT_PLAIN.cover?(adjusted)

        "#{"-" if value.coefficient.negative?}#{scientific(digits)}E#{adjusted}"
      end

      # A DECFLOAT's digits written out, its exponent's zeros or point.
      #
      # @api private
      def numeral(coefficient, exponent)
        exponent.negative? ? Decimal.new(units: coefficient, scale: -exponent).to_s : "#{coefficient}#{"0" * exponent}"
      end

      # A date, time or timestamp as shown in its zone: its date, its time
      # to its precision, its displacement if WITH TIME ZONE.
      #
      # @api private
      def datetime(value, _type = nil)
        days, time = (value.utc + (value.zone * MICROS[:minute])).divmod(MICROS[:day])
        return civil(days) if value.moment == :date

        shown = clock(time, value.precision) + zoned(value)
        value.moment == :time ? shown : "#{civil(days)} #{shown}"
      end

      # The displacement of a datetime WITH TIME ZONE; nothing of another.
      #
      # @api private
      def zoned(value)
        value.zoned ? displacement(value.zone) : ""
      end

      # The date +days+ after 0001-01-01, as YYYY-MM-DD.
      #
      # @api private
      def civil(days)
        era, day_of_era = (days + ERA_SHIFT).divmod(146_097)
        year_of_era = year_of(day_of_era)
        month, day = month_day(day_of_era - ((365 * year_of_era) + (year_of_era / 4) - (year_of_era / 100)))
        format("%<year>04d-%<month>02d-%<day>02d", year: (era * 400) + year_of_era + (month <= 2 ? 1 : 0), month:, day:)
      end

      # The year of a 400-year era its +day_of_era+th day is in.
      #
      # @api private
      def year_of(day_of_era)
        (day_of_era - (day_of_era / 1460) + (day_of_era / 36_524) - (day_of_era / 146_096)) / 365
      end

      # The month and day of the +day_of_year+th day of a year begun in
      # March.
      #
      # @api private
      def month_day(day_of_year)
        shifted = ((5 * day_of_year) + 2) / 153
        [shifted < 10 ? shifted + 3 : shifted - 9, day_of_year - (((153 * shifted) + 2) / 5) + 1]
      end

      # The time +micros+ from midnight, to +precision+ digits of the
      # second.
      #
      # @api private
      def clock(micros, precision)
        seconds, fraction = micros.divmod(MICROS[:second])
        text = format("%<h>02d:%<m>02d:%<s>02d", h: seconds / 3600, m: (seconds / 60) % 60, s: seconds % 60)
        precision.positive? ? "#{text}.#{format("%06d", fraction)[0, precision]}" : text
      end

      # A zone's displacement, as +05:30.
      #
      # @api private
      def displacement(zone)
        hours, minutes = zone.abs.divmod(60)
        format("%<sign>s%<h>02d:%<m>02d", sign: zone.negative? ? "-" : "+", h: hours, m: minutes)
      end

      # An interval as its literal's string: its sign, its leading field's
      # digits, each other field two after its separator, the second's
      # fraction to its precision.
      #
      # @api private
      def interval(value, _type = nil)
        fields = FIELDS[RANKS.fetch(value.start)..RANKS.fetch(value.finish)].to_a
        sign = value.units.negative? ? "-" : ""
        sign + fields.map.with_index { |field, index| interval_field(value, field, index) }.join
      end

      # The text of +field+ of +value+, the +index+th of its fields.
      #
      # @api private
      def interval_field(value, field, index)
        n = field_value(value.units.abs, field, index)
        return whole_field(n, field, index) unless field == :second

        text = whole_field(n / MICROS[:second], field, index)
        value.fraction.positive? ? "#{text}.#{format("%06d", n % MICROS[:second])[0, value.fraction]}" : text
      end

      # The whole units +n+ of +field+, the +index+th: its digits, or two
      # after its separator.
      #
      # @api private
      def whole_field(number, field, index)
        index.zero? ? number.to_s : "#{SEPARATORS.fetch(field)}#{format("%02d", number)}"
      end

      # The units of +field+ of an interval of +size+ units: of the second,
      # its microseconds.
      #
      # @api private
      def field_value(size, field, index)
        above = index.zero? ? size : size % FIELD_UNITS.fetch(FIELDS.fetch(RANKS.fetch(field) - 1))
        field == :second ? above : above / FIELD_UNITS.fetch(field)
      end

      # A large object: its text or its octets in hexadecimal if held
      # whole, else what it is.
      #
      # @api private
      def lob(value, _type = nil)
        data = value.data
        return value.kind == :character ? data.dup.force_encoding(Encoding::UTF_8).scrub : hex(data) if data

        what = value.kind == :character ? "CHARACTER LARGE OBJECT of #{value.characters} characters" : nil
        "<#{what || "BINARY LARGE OBJECT of #{value.octets} octets"}>"
      end

      # +octets+ in upper-case hexadecimal.
      #
      # @api private
      def hex(octets) = octets.unpack1("H*").to_s.upcase

      # A character string quoted, a binary one as X'...'.
      #
      # @api private
      def string_literal(value, _type) = value.encoding == Encoding::BINARY ? "X'#{hex(value)}'" : quoted(value)

      # An array, as ARRAY[...] of its elements' literals.
      #
      # @api private
      def array_literal(value, type) = "ARRAY[#{literals(value, type&.params&.dig(:element))}]"

      # A datetime, as its key word and its string.
      #
      # @api private
      def datetime_literal(value, _type) = "#{value.moment.to_s.upcase} '#{datetime(value)}'"

      # A DECFLOAT, cast from its text.
      #
      # @api private
      def decfloat_literal(value, _type) = "CAST('#{decfloat(value)}' AS DECFLOAT)"

      # A row value, as ROW(...).
      #
      # @api private
      def row_literal(value, _type) = "ROW(#{literals(value.values, nil)})"

      # A multiset, as MULTISET[...].
      #
      # @api private
      def multiset_literal(value, _type) = "MULTISET[#{literals(value.values, nil)}]"

      # A structured value, as its type's constructor of its attributes.
      #
      # @api private
      def structured_literal(value, _type) = "#{value.schema}.#{value.name}(#{literals(value.attributes, nil)})"

      # A reference, as REF(...) of its octets.
      #
      # @api private
      def reference_literal(value, _type) = "REF(#{hex(value.octets)})"

      # A JSON value, as JSON(...) of its text.
      #
      # @api private
      def json_literal(value, _type) = "JSON(#{quoted(Text::Json.shown(value.value))})"

      # A UUID, as UUID and its text.
      #
      # @api private
      def uuid_literal(value, _type) = "UUID '#{value.text}'"

      # An XML value, as XMLPARSE of its text.
      #
      # @api private
      def xml_literal(value, _type) = "XMLPARSE(CONTENT #{quoted(value.text)} PRESERVE WHITESPACE)"

      # An interval's literal: INTERVAL, its sign, its string, its
      # qualifier.
      #
      # @api private
      def interval_literal(value, _type)
        text = interval(value)
        "INTERVAL #{"-" if text.start_with?("-")}'#{text.delete_prefix("-")}' #{qualifier(value)}"
      end

      # An interval's qualifier as SQL writes it.
      #
      # @api private
      def qualifier(value)
        start = value.start.to_s.upcase
        second = value.finish == :second
        if value.start == value.finish
          return second ? "SECOND(#{value.leading}, #{value.fraction})" : "#{start}(#{value.leading})"
        end

        "#{start}(#{value.leading}) TO #{value.finish.to_s.upcase}#{"(#{value.fraction})" if second}"
      end

      # A large object's literal: its text quoted, or its octets.
      #
      # @api private
      def lob_literal(value, _type)
        data = value.data
        return lob(value) unless data

        value.kind == :character ? quoted(data) : "X'#{hex(data)}'"
      end

      # The literals of +values+, each of +type+, between commas.
      #
      # @api private
      def literals(values, type) = values.map { |v| literal(v, type) }.join(", ")

      # +text+ quoted, a quote in it written twice.
      #
      # @api private
      def quoted(text) = "'#{text.gsub("'", "''")}'"
    end
  end
end
