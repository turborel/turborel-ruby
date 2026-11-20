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
