# frozen_string_literal: true

module Turborel
  module Protocol
    # The composite fields [PROTOCOL Composite fields]: a column, a
    # parameter and a failure, with a failure's or a notice's diagnostics
    # [PROTOCOL Errors and notices].
    #
    # @api private
    module Fields
      # The diagnostics' fields, in the order of their tags from 7
      # [PROTOCOL Errors and notices].
      DIAGNOSTICS = %i[severity detail hint context schema table column data_type constraint].freeze
      # The tags of the diagnostics.
      DIAGNOSTIC_TAGS = (Tail::SEVERITY..Tail::CONSTRAINT)

      # A column: named flag, its name if named, its data type, its not
      # null flag.
      #
      # @param reader [Reader]
      # @return [Column]
      def self.column(reader)
        named = reader.flag
        name = named ? reader.str : nil
        Column.new(name:, type: Types.read(reader), not_null: reader.flag)
      end

      # The modes of a CALL's parameters, by their codes [PROTOCOL Parameter
      # modes].
      MODES = { 1 => :in, 2 => :inout, 4 => :out }.freeze

      # Tag 20's body, called: the procedure's specific schema and name,
      # then each ? in written order, its mode, ordinal position from 1 and
      # parameter [PROTOCOL Parameter modes].
      #
      # @param reader [Reader]
      # @return [Called]
      # @raise [Error] a connection failure of a mode of another code, or a
      #   position of 0
      def self.called(reader)
        schema = reader.str
        name = reader.str
        Called.new(schema:, name:, parameters: reader.counted { called_parameter(reader) })
      end

      # A ? of tag 20: its mode, ordinal position and parameter.
      #
      # @param reader [Reader]
      # @return [CalledParameter]
      def self.called_parameter(reader)
        code = reader.u8
        mode = MODES.fetch(code) { raise reader.corrupt("#{code} is no parameter's mode") }
        ordinal = reader.u32
        raise reader.corrupt("a parameter's position is 0") if ordinal.zero?

        CalledParameter.new(mode:, ordinal:, parameter: parameter(reader))
      end

      # A parameter: varying flag, then its data type.
      #
      # @param reader [Reader]
      # @return [Parameter]
      def self.parameter(reader)
        varying = reader.flag
        Parameter.new(varying:, type: Types.read(reader))
      end

      # A failure: SQLCODE as u32, SQLSTATE, message, cited flag and rule,
      # placed flag and position, active flag, then its diagnostics, tags 7
      # to 15, to the end of what +reader+ reads.
      #
      # @param reader [Reader]
      # @return [Failure]
      def self.failure(reader)
        sqlcode = ValueReader.signed32(reader.u32)
        sqlstate = reader.str
        message = reader.str
        rule = reader.flag ? reader.str : nil
        position = reader.flag ? reader.u64 : nil
        active = reader.flag
        Failure.new(sqlcode:, sqlstate:, message:, rule:, position:, active:, diagnostics: diagnostics(reader))
      end

      # The diagnostics of a tail of diagnostics alone, to the end of what
      # +reader+ reads: +nil+ if it is empty.
      #
      # @param reader [Reader]
      # @return [Diagnostics, nil]
      def self.diagnostics(reader)
        found = {} # : Hash[Symbol, String]
        Tail.new(reader, DIAGNOSTIC_TAGS).each_tag do |tag|
          found[DIAGNOSTICS.fetch(tag - Tail::SEVERITY)] = reader.str
        end
        return nil if found.empty?

        Diagnostics.new(**DIAGNOSTICS.to_h { |field| [field, found[field]] })
      end
    end
  end
end
