# frozen_string_literal: true

module Turborel
  module Text
    # A JSON value's text as turborel writes it (src/json/serialize.rs): no
    # insignificant white space; an object's members in their order; a
    # string's quotation marks, reverse solidi and control characters
    # escaped, nothing else; an exact number's digits and its scale's, an
    # approximate one's shortest literal, a DECFLOAT plain; true, false and
    # null. No text is of a datetime or an approximate number not finite.
    module Json
      # The two-character escapes of a string [RFC 8259 §7].
      ESCAPES = { '"' => '\\"', "\\" => "\\\\", "\b" => "\\b", "\f" => "\\f", "\n" => "\\n", "\r" => "\\r",
                  "\t" => "\\t" }.freeze
      # What turborel says of an item no JSON text is.
      NO_TEXT = "[ISO/IEC 9075-2:2023 §9.43 GR2a ii] no JSON text parses to"

      # The text of +item+, or what turborel shows of one no JSON text is:
      # why, in angle brackets.
      #
      # @param item [Object] a JSON value's item as the driver reads it
      # @return [String]
      def self.shown(item)
        of(item)
      rescue NoText => e
        "<#{e.message}>"
      end

      # @return [String] the JSON text of +item+
      # @raise [NoText] of an item that is or holds a datetime or an
      #   approximate number not finite
      def self.of(item)
        case item
        when Hash then "{#{item.map { |key, value| "#{string(key.to_s)}:#{of(value)}" }.join(",")}}"
        when Array then "[#{item.map { |element| of(element) }.join(",")}]"
        else scalar(item)
        end
      end

      # The text of a scalar item.
      def self.scalar(item)
        case item
        when nil, true, false then item.nil? ? "null" : item.to_s
        when String, Symbol then string(item.to_s)
        when Numeric, Turborel::Decimal, DecFloat then number(item)
        else raise NoText, "#{NO_TEXT} a datetime"
        end
      end

      # The text of a number.
      def self.number(item)
        case item
        when Float then approximate(item)
        when BigDecimal then Text.exact(item, nil)
        when DecFloat then Text.numeral(item.coefficient, item.exponent)
        else item.to_s
        end
      end

      # CAST's approximate literal of +value+: a point in its mantissa.
      def self.approximate(value)
        raise NoText, "#{NO_TEXT} an approximate number that is not finite" unless value.finite?
        return "0E0" if value.zero?

        mantissa, exponent = Text.approximate(value).split("E").map(&:to_s)
        mantissa.to_s.include?(".") ? "#{mantissa}E#{exponent}" : "#{mantissa}.0E#{exponent}"
      end

      # +text+ as a JSON string.
      def self.string(text)
        escaped = text.each_char.map do |char|
          ESCAPES.fetch(char) { char.ord <= 0x1F ? format("\\u%04x", char.ord) : char }
        end
        "\"#{escaped.join}\""
      end

      # An item no JSON text is.
      class NoText < StandardError; end
    end
  end
end
