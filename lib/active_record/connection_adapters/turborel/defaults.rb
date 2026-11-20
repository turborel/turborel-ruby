# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    # The Turborel adapter's parts (RULES.md D2).
    module Turborel
      # What INFORMATION_SCHEMA.COLUMNS and REFERENTIAL_CONSTRAINTS say, read
      # as ActiveRecord takes it (RULES.md D2).
      module Defaults
        # The types written with what follows them: their length, their
        # precision and scale, or their seconds' precision, each as the
        # columns of INFORMATION_SCHEMA.COLUMNS that give it.
        SUFFIXES = {
          "CHARACTER" => ["CHARACTER_MAXIMUM_LENGTH"], "CHARACTER VARYING" => ["CHARACTER_MAXIMUM_LENGTH"],
          "BINARY" => ["CHARACTER_MAXIMUM_LENGTH"], "BINARY VARYING" => ["CHARACTER_MAXIMUM_LENGTH"],
          "DECIMAL" => %w[NUMERIC_PRECISION NUMERIC_SCALE], "NUMERIC" => %w[NUMERIC_PRECISION NUMERIC_SCALE],
          "TIME" => ["DATETIME_PRECISION"], "TIMESTAMP" => ["DATETIME_PRECISION"]
        }.freeze
        # A character string literal, its quotes doubled.
        STRING = /\A'((?:[^']|'')*)'\z/
        # A numeric literal.
        NUMBER = /\A[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:E[+-]?\d+)?\z/i
        # A typed literal: a datetime's, an interval's, a binary string's.
        TYPED = /\A(?:DATE|TIME|TIMESTAMP|INTERVAL|X)\s*'((?:[^']|'')*)'/i
        # The referential actions, as ForeignKeyDefinition names them.
        ACTIONS = { "CASCADE" => :cascade, "SET NULL" => :nullify, "RESTRICT" => :restrict }.freeze

        # The SQL type of +field+, a row of the columns' definitions, as its
        # column was declared: its length, precision and scale after it.
        #
        # @param field [Hash{String => Object}]
        # @return [String]
        def self.sql_type(field)
          type = field["DATA_TYPE"].to_s
          first, *rest = SUFFIXES.fetch(type, []).map { |name| field[name] }
          return type if first.nil?

          "#{type}(#{[first, *rest.map { |value| value || 0 }].join(",")})"
        end

        # The value of +default+, a column's default as written: a literal's
        # text, TRUE or FALSE; nil of NULL, of none and of an expression,
        # which is the column's default function.
        #
        # @param default [String, nil]
        # @return [String, nil]
        def self.value(default)
          case default
          when nil, "NULL" then nil
          when STRING, TYPED then Regexp.last_match(1).to_s.gsub("''", "'")
          when NUMBER, "TRUE", "FALSE" then default
          end
        end

        # +rule+, a referential action, as ForeignKeyDefinition names it;
        # nil of NO ACTION.
        #
        # @param rule [String]
        # @return [Symbol, nil]
        def self.action(rule) = ACTIONS[rule]
      end
    end
  end
end
