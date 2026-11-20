# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    # The Turborel adapter's parts (RULES.md D2).
    module Turborel
      # Names and values written into SQL as Turborel reads them (RULES.md
      # D2): identifiers in double quotes, a string's quote doubled and no
      # other character escaped, datetimes as typed literals, and bound
      # values as Appendix A writes them.
      module Quoting
        extend ActiveSupport::Concern

        # The quoting of names, the adapter's own.
        module ClassMethods
          # +name+ as a delimited identifier.
          #
          # @param name [String, Symbol]
          # @return [String]
          def quote_column_name(name) = %("#{name.to_s.gsub('"', '""')}")

          # +name+, a table's, a schema's before it after a dot, as
          # delimited identifiers.
          #
          # @param name [String, Symbol]
          # @return [String]
          def quote_table_name(name) = name.to_s.split(".", 2).map { |part| quote_column_name(part) }.join(".")
        end

        # +string+ within a character string literal: its quotes doubled.
        #
        # @param string [String]
        # @return [String]
        def quote_string(string) = string.gsub("'", "''")

        # +value+ as an SQL literal: a datetime typed, a binary string in
        # hexadecimal.
        #
        # @param value [Object]
        # @return [String]
        def quote(value)
          case value
          when Type::Time::Value then "TIME '#{quoted_time(value)}'"
          when Date, Time then "#{value.acts_like?(:time) ? "TIMESTAMP" : "DATE"} '#{quoted_date(value)}'"
          else super
          end
        end

        # A binary string as a binary string literal.
        #
        # @param value [ActiveModel::Type::Binary::Data]
        # @return [String]
        def quoted_binary(value) = "X'#{value.hex}'"

        # +value+, bound, as Appendix A writes it: a datetime as a
        # Turborel::Datetime of its wall clock, a decimal exactly.
        #
        # @param value [Object]
        # @return [Object]
        def type_cast(value)
          case value
          when Type::Time::Value then Values.time(value)
          when Type::Binary::Data then value.to_s.b
          when BigDecimal then value
          when Date, Time
            value.acts_like?(:time) ? Values.timestamp(value, default_timezone) : Values.date(value)
          else super
          end
        end
      end
    end
  end
end
