# frozen_string_literal: true

module Turborel
  module Import
    # A string assigned to a character string column as INSERT assigns it
    # [ISO/IEC 9075:1992 §13.8 GR4b iii, §9.2 GR3b, GR3e], as turborel's
    # assign does, so a string too long is refused, not cut: of CHARACTER,
    # padded with spaces to its length; of CHARACTER VARYING, as it is; of
    # CHARACTER LARGE OBJECT, a large object held whole; each without the
    # spaces past the length, and refused if more than spaces are past it.
    #
    # @api private
    module Assign
      # The rule by which INSERT assigns a value to its column.
      INSERT_ASSIGNS = "ISO/IEC 9075:1992 §13.8 GR4b iii"
      # SQLSTATE of a string too long: string data, right truncation.
      RIGHT_TRUNCATION = "22001"
      # The kinds of the character string types.
      CHARACTER_KINDS = %i[character varying clob].freeze

      # +values+ as they are sent for parameters of +parameters+: a String
      # for a character string column assigned to it, any other value as it
      # is, for the server to cast.
      #
      # @param values [Array]
      # @param parameters [Array<Parameter>]
      # @return [Array]
      # @raise [Error] SQLSTATE 22001 of a string too long for its column
      def self.assigned(values, parameters)
        values.zip(parameters).map do |value, parameter|
          type = parameter&.type
          value.is_a?(String) && type && CHARACTER_KINDS.include?(type.kind) ? string(value, type) : value
        end
      end

      # +text+ assigned to the character string type +type+.
      def self.string(text, type)
        octets = type.params[:units] == :octets
        length = type.params[:length]
        count = octets ? text.bytesize : text.size
        kept = count <= length ? text : prefix(text, length, octets)
        return assigned_to(kept, type, length, octets) if count <= length || text[kept.size..].to_s.match?(/\A *\z/)

        raise refused(type, count, length, octets)
      end

      # +kept+, which fits, as the type holds it.
      def self.assigned_to(kept, type, length, octets)
        case type.kind
        when :character then kept + (" " * (length - (octets ? kept.bytesize : kept.size)))
        when :clob
          Lob.new(kind: :character, data: kept, locator: nil, octets: kept.bytesize, characters: kept.size)
        else kept
        end
      end

      # The longest start of +text+ of at most +most+ characters, or
      # octets, whole characters.
      def self.prefix(text, most, octets)
        return text[0, most] || "" unless octets

        text.byteslice(0, most).to_s.scrub("")
      end

      # The failure of a string of +count+ units too long for +type+: its
      # rule, the INSERT's and the assignment's, apart from its message, as
      # turborel's own failure carries it.
      def self.refused(type, count, length, octets)
        rule, message = if type.kind == :clob
                          ["#{INSERT_ASSIGNS}; ISO/IEC 9075-2:2023 §9.2 GR3e ii",
                           "a large object longer than #{written(type)}, not padding beyond it, does not fit it"]
                        else
                          ["#{INSERT_ASSIGNS}, #{type.kind == :character ? "§9.2 GR3b ii" : "§9.2 GR3e ii"}",
                           "a value of #{count} #{octets ? "octets" : "characters"}, not spaces beyond #{length}, " \
                           "does not fit #{written(type)}"]
                        end
        Error.new(Failure.new(sqlcode: Error::DATA_EXCEPTION_SQLCODE, sqlstate: RIGHT_TRUNCATION, message:, rule:,
                              position: nil, active: false, diagnostics: nil))
      end

      # A character string type as SQL writes it.
      def self.written(type)
        name = { character: "CHARACTER", varying: "CHARACTER VARYING", clob: "CHARACTER LARGE OBJECT" }.fetch(type.kind)
        type.params[:units] == :octets ? "#{name}(#{type.params[:length]} OCTETS)" : "#{name}(#{type.params[:length]})"
      end
    end
  end
end
