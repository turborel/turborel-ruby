# frozen_string_literal: true

module Turborel
  module Text
    # A data type as SQL writes it, as turborel writes a type its tag says
    # (src/value/types/*.rs, written): what a column's type_written gives
    # when the server did not tell its declared type [CLIENT Prepared
    # statements].
    module Types
      # The name each kind is written with, of the kinds of no parameter
      # or whose parameters follow it in parentheses.
      NAMES = {
        character: "CHARACTER", varying: "CHARACTER VARYING", clob: "CHARACTER LARGE OBJECT",
        blob: "BINARY LARGE OBJECT", binary: "BINARY", varbinary: "BINARY VARYING", boolean: "BOOLEAN",
        json: "JSON", uuid: "UUID", date: "DATE", decfloat: "DECFLOAT"
      }.freeze
      # How each kind is written: the method of this module.
      WRITERS = {
        character: :lengthed, varying: :lengthed, clob: :lob, blob: :lob, binary: :sized, varbinary: :sized,
        exact: :exact, approximate: :approximate, decfloat: :decfloat, date: :named, boolean: :named,
        json: :named, uuid: :named, time: :moment, time_zoned: :moment, timestamp: :moment,
        timestamp_zoned: :moment, interval: :interval, array: :array, multiset: :multiset, row: :row,
        structured: :structured, reference: :reference, xml: :xml, extension: :extension
      }.freeze
      # The datetime kinds, each its name and whether it is WITH TIME ZONE.
      MOMENTS = {
        time: ["TIME", false], time_zoned: ["TIME", true], timestamp: ["TIMESTAMP", false],
        timestamp_zoned: ["TIMESTAMP", true]
      }.freeze #: Hash[Symbol, [String, bool]]

      # The name of each kind, as the Information Schema's DATA_TYPE gives
      # it, of a type its tag says.
      DATA_TYPES = NAMES.merge(
        exact: "NUMERIC", approximate: "FLOAT", time: "TIME", time_zoned: "TIME WITH TIME ZONE",
        timestamp: "TIMESTAMP", timestamp_zoned: "TIMESTAMP WITH TIME ZONE", interval: "INTERVAL",
        array: "ARRAY", multiset: "MULTISET", row: "ROW", structured: "USER-DEFINED", reference: "REF",
        xml: "XML"
      ).freeze

      # +type+ as SQL writes it.
      #
      # @param type [DataType]
      # @return [String]
      def self.written(type) = send(WRITERS.fetch(type.kind), type, type.params)

      # The name of +type+, as the Information Schema's DATA_TYPE gives it:
      # a plug-in's type by its own name.
      #
      # @param type [DataType]
      # @return [String]
      def self.name(type) = type.kind == :extension ? type.params[:name] : DATA_TYPES.fetch(type.kind)

      class << self
        private

        # A character string type: its length, and OCTETS if it counts them.
        def lengthed(type, params) = "#{NAMES.fetch(type.kind)}(#{params[:length]}#{" OCTETS" if octets?(params)})"

        # A large object type, OCTETS only of a character one.
        def lob(type, params)
          octets = octets?(params) && type.kind == :clob
          "#{NAMES.fetch(type.kind)}(#{params[:length]}#{" OCTETS" if octets})"
        end

        # Whether a type counts its length in octets.
        def octets?(params) = params[:units] == :octets

        # A binary string type and its length.
        def sized(type, params) = "#{NAMES.fetch(type.kind)}(#{params[:length]})"

        # An exact numeric type, as a tag writes it: NUMERIC.
        def exact(_type, params) = "NUMERIC(#{params[:precision]},#{params[:scale]})"

        # An approximate numeric type, as a tag writes it: FLOAT.
        def approximate(_type, params) = "FLOAT(#{params[:precision]})"

        # DECFLOAT and its precision.
        def decfloat(_type, params) = "DECFLOAT(#{params[:precision]})"

        # A type of no parameter.
        def named(type, _params) = NAMES.fetch(type.kind)

        # A time or a timestamp, its precision, WITH TIME ZONE if zoned.
        def moment(type, params)
          name, zoned = MOMENTS.fetch(type.kind)
          "#{name}(#{params[:precision]})#{" WITH TIME ZONE" if zoned}"
        end

        # An interval type and its qualifier.
        def interval(_type, params) = "INTERVAL #{qualifier(params)}"

        # An interval qualifier as turborel writes it.
        def qualifier(params)
          start = params[:start].to_s.upcase
          finish = params[:finish].to_s.upcase
          if params[:start] == params[:finish]
            return "SECOND(#{params[:leading]}, #{params[:fraction]})" if params[:finish] == :second

            return "#{start}(#{params[:leading]})"
          end
          "#{start}(#{params[:leading]}) TO #{finish}#{"(#{params[:fraction]})" if params[:finish] == :second}"
        end

        # An array type: its element type, then ARRAY and its maximum.
        def array(_type, params) = "#{written(params[:element])} ARRAY[#{params[:max]}]"

        # A multiset type: its element type, then MULTISET.
        def multiset(_type, params) = "#{written(params[:element])} MULTISET"

        # A row type: each field's name and type.
        def row(_type, params) = "ROW(#{params[:fields].map { |name, type| "#{name} #{written(type)}" }.join(", ")})"

        # A structured type, by its schema and name.
        def structured(_type, params) = "#{params[:schema]}.#{params[:name]}"

        # A reference type, its referenced type's name and its scope.
        def reference(_type, params)
          scope = params[:scope]
          "REF(#{params[:name]})#{" SCOPE #{scope.join(".")}" if scope}"
        end

        # An XML type and its modifiers.
        def xml(_type, params)
          primary = params[:primary].to_s.upcase
          schema = params[:schema]
          return "XML(#{primary}(XMLSCHEMA #{according(schema)}))" if schema
          return "XML(#{primary})" if params[:primary] == :sequence

          "XML(#{primary}(#{params[:secondary].to_s.upcase}))"
        end

        # What an XML type's XMLSCHEMA names, as turborel writes it.
        def according(schema)
          namespace = schema[:namespace]
          element = schema[:element]
          text = "ID #{schema[:schema]}.#{schema[:name]}"
          text << (namespace.empty? ? " NO NAMESPACE" : " NAMESPACE '#{namespace.gsub("'", "''")}'") if namespace
          text << " ELEMENT \"#{element.gsub('"', '""')}\"" if element
          text
        end

        # A plug-in's type, by its name.
        def extension(_type, params) = params[:name]
      end
    end
  end
end
