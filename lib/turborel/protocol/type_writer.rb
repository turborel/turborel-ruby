# frozen_string_literal: true

module Turborel
  module Protocol
    # Data types written as the server writes them [PROTOCOL Data types],
    # Types.read's inverse: what an export as the protocol's own frames
    # writes of its columns.
    #
    # @api private
    module TypeWriter
      # How each kind's parameters are written: the method of this module.
      PARAMS = Types::PARAMS

      # Writes +type+, its tag then its parameters.
      #
      # @param writer [Writer]
      # @param type [DataType]
      # @return [void]
      def self.write(writer, type)
        writer.u8(Types.tag(type.kind))
        send(PARAMS.fetch(type.kind), writer, type.params)
      end

      # Writes a column: named flag, its name if named, its type, its not
      # null flag [PROTOCOL Composite fields].
      #
      # @param writer [Writer]
      # @param column [Column]
      # @return [void]
      def self.column(writer, column)
        name = column.name
        writer.flag(!name.nil?)
        writer.str(name) if name
        write(writer, column.type)
        writer.flag(column.not_null)
      end

      # @return [void]
      def self.nothing(_writer, _params) = nil

      # @return [void]
      def self.length_units(writer, params) = writer.u32(params[:length]).u8(units(params))

      # @return [void]
      def self.precision_scale(writer, params) = writer.u32(params[:precision]).u32(params[:scale])

      # @return [void]
      def self.precision(writer, params) = writer.u32(params[:precision])

      # @return [void]
      def self.length(writer, params) = writer.u32(params[:length])

      # @return [void]
      def self.lob_length(writer, params) = writer.u64(params[:length]).u8(units(params))

      # @return [void]
      def self.qualifier(writer, params)
        writer.u32(Types::FIELDS.index(params[:start]) || 0).u32(Types::FIELDS.index(params[:finish]) || 0)
        writer.u32(params[:leading]).u32(params[:fraction])
      end

      # @return [void]
      def self.array(writer, params)
        writer.u32(params[:max])
        write(writer, params[:element])
      end

      # @return [void]
      def self.multiset(writer, params) = write(writer, params[:element])

      # @return [void]
      def self.row(writer, params)
        writer.u32(params[:fields].size)
        params[:fields].each do |name, type|
          writer.str(name)
          write(writer, type)
        end
      end

      # @return [void]
      def self.structured(writer, params)
        writer.str(params[:schema]).str(params[:name]).u32(params[:supertypes].size)
        params[:supertypes].each { |schema, name| writer.str(schema).str(name) }
      end

      # @return [void]
      def self.reference(writer, params)
        structured(writer, params)
        scope = params[:scope]
        writer.u8(scope ? 1 : 0)
        writer.str(scope[0]).str(scope[1]) if scope
      end

      # @return [void]
      def self.xml(writer, params)
        writer.u8(Types::XML_PRIMARY.key(params[:primary]) || 0).u8(Types::XML_SECONDARY.key(params[:secondary]) || 0)
        schema = params[:schema]
        return unless schema

        writer.str(schema[:schema]).str(schema[:name])
        [schema[:namespace], schema[:element]].each { |text| optional(writer, text) }
      end

      # @return [void]
      def self.extension(writer, params)
        writer.str(params[:name]).u32(params[:params].size)
        params[:params].each { |param| writer.u32(param) }
      end

      # @return [Integer] a character type's units' byte
      def self.units(params) = Types::UNITS.key(params[:units]) || 0

      # Writes 0 for none, or 1 and +text+.
      #
      # @return [void]
      def self.optional(writer, text)
        writer.flag(!text.nil?)
        writer.str(text) if text
      end
    end
  end
end
