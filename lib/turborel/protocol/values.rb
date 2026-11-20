# frozen_string_literal: true

require "bigdecimal"

module Turborel
  module Protocol
    # Values as the protocol writes them [PROTOCOL Values]: a tag, then its
    # body. Each value's tag says how it is written, which is not always
    # its column's type's: a CHARACTER VARYING value comes with tag 1.
    #
    # Read, a value becomes a Ruby value: +nil+, a String (UTF-8 of a
    # character string, binary of a binary string), an Integer (an exact
    # number of scale 0) or a BigDecimal (of a scale above 0), a Float,
    # +true+ or +false+, an Array, or one of the driver's value classes.
    # ValueWriter writes them back.
    #
    # @api private
    module Values
      # The tags of values [PROTOCOL Values], UUID's 27 among them
      # (turborel RULES.md D184).
      NULL = 0
      # (see NULL)
      CHARACTER = 1
      # (see NULL)
      EXACT = 2
      # (see NULL)
      APPROXIMATE = 3
      # (see NULL)
      EXTENSION = 4
      # (see NULL)
      BINARY = 6
      # (see NULL)
      DATE = 8
      # (see NULL)
      TIME = 9
      # (see NULL)
      TIMESTAMP = 11
      # (see NULL)
      INTERVAL = 13
      # (see NULL)
      BOOLEAN = 14
      # (see NULL)
      DECFLOAT = 15
      # (see NULL)
      ARRAY = 16
      # (see NULL)
      ROW = 17
      # (see NULL)
      LOB_WHOLE = 20
      # (see NULL)
      LOB_LOCATOR = 21
      # (see NULL)
      MULTISET = 22
      # (see NULL)
      STRUCTURED = 23
      # (see NULL)
      REFERENCE = 24
      # (see NULL)
      JSON = 25
      # (see NULL)
      XML = 26
      # (see NULL)
      UUID = 27
      # The moment of each datetime tag, and back.
      MOMENTS = { DATE => :date, TIME => :time, TIMESTAMP => :timestamp }.freeze
      # A large object's kind byte, and back [PROTOCOL Values].
      LOB_KINDS = { 0 => :character, 1 => :binary }.freeze
      # The octets of a UUID.
      UUID_OCTETS = 16
      # The most elements a multiset holds, turborel's
      # MAX_MULTISET_CARDINALITY.
      MAX_MULTISET_CARDINALITY = 65_535
      # The largest displacement field: a zone's minutes are an i16's bits
      # in the low half of a u32 [PROTOCOL Values].
      MAX_ZONE_FIELD = 0xFFFF
      # The bias of an i16 held in 16 unsigned bits.
      I16_BIAS = 0x1_0000
      # The largest i16.
      MAX_I16 = 0x7FFF
      # The most digits of a DECFLOAT's coefficient, turborel's
      # MAX_DECFLOAT_PRECISION.
      DECFLOAT_DIGITS = 34
      # The range of a DECFLOAT's adjusted exponent, turborel's
      # MIN_EXPONENT and MAX_EXPONENT.
      DECFLOAT_ADJUSTED = (-6143)..6144
      # Ten, the radix of exact numbers.
      RADIX = 10
      # The digit at which a dropped digit rounds up, or to even.
      HALF = 5
      # The most digits an i128 holds, past which an exact number's units
      # are not even computed.
      I128_DIGITS = 39
      # The sign bit of an i32 held in a u32.
      I32_SIGN = 0x8000_0000
      # The bias of an i32 held in a u32.
      I32_BIAS = 0x1_0000_0000
      # How each tag's body is read: the method of ValueReader.
      READERS = {
        NULL => :null, CHARACTER => :character, EXACT => :exact, APPROXIMATE => :approximate,
        EXTENSION => :extension, BINARY => :binary, DATE => :datetime, TIME => :datetime,
        TIMESTAMP => :datetime, INTERVAL => :interval, BOOLEAN => :boolean, DECFLOAT => :decfloat,
        ARRAY => :array, ROW => :row, LOB_WHOLE => :lob_whole, LOB_LOCATOR => :lob_locator,
        MULTISET => :multiset, STRUCTURED => :structured, REFERENCE => :reference, JSON => :json,
        XML => :xml, UUID => :uuid
      }.freeze

      # Whether +coefficient+ and +exponent+ are a DECFLOAT in its one
      # form: zero as 0 and 0; else no trailing zero, at most 34 digits,
      # and an adjusted exponent in range, as turborel's DecFloat::new
      # leaves them unchanged.
      #
      # @param coefficient [Integer]
      # @param exponent [Integer]
      # @return [Boolean]
      def self.decfloat?(coefficient, exponent)
        rounded_decfloat(coefficient, exponent) == DecFloat.new(coefficient:, exponent:)
      end

      # +coefficient+ times ten to +exponent+ as turborel's DecFloat::new
      # makes it: rounded half to even to 34 digits, its trailing zeros
      # taken into the exponent, zero as 0 and 0; +nil+ if its adjusted
      # exponent is out of range or its exponent does not fit an i32.
      #
      # @param coefficient [Integer]
      # @param exponent [Integer]
      # @return [DecFloat, nil]
      def self.rounded_decfloat(coefficient, exponent)
        magnitude, exponent = rounded(coefficient.abs, exponent)
        return DecFloat.new(coefficient: 0, exponent: 0) if magnitude.zero?

        while (magnitude % RADIX).zero?
          magnitude /= RADIX
          exponent += 1
        end
        within = DECFLOAT_ADJUSTED.cover?(exponent + magnitude.to_s.size - 1) && Writer::I32_RANGE.cover?(exponent)
        DecFloat.new(coefficient: coefficient.negative? ? -magnitude : magnitude, exponent:) if within
      end

      # +magnitude+ and +exponent+ rounded half to even to 34 digits, the
      # digits dropped raising the exponent.
      #
      # @return [Array(Integer, Integer)]
      def self.rounded(magnitude, exponent)
        dropped = 0
        sticky = false
        [magnitude.to_s.size - DECFLOAT_DIGITS, 0].max.times do
          sticky ||= !dropped.zero?
          magnitude, dropped = magnitude.divmod(RADIX)
          exponent += 1
        end
        up = dropped > HALF || (dropped == HALF && (sticky || magnitude.odd?))
        [up ? magnitude + 1 : magnitude, exponent]
      end
    end
  end
end
