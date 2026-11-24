# frozen_string_literal: true

module Turborel
  module Protocol
    # *(extension)* The fields of Debugged and Event [PROTOCOL Debugged
    # 'V'] [PROTOCOL Event 'W']: a breakpoint, a pause and its frames, each
    # read whole. A code no field has fails the connection.
    #
    # @api private
    module DebugFields
      # What a Debugged answers, by its code.
      ANSWERS = { 0 => :connection, 1 => :breakpoint, 2 => :breakpoints, 3 => :stack }.freeze
      # An Event's kinds, by their codes.
      EVENTS = { 0 => :paused, 1 => :timed_out, 2 => :cancelled, 3 => :ended }.freeze
      # Why a target paused, by its code.
      REASONS = { 0 => :breakpoint, 1 => :step }.freeze

      # Debugged's what and its body: a connection's ID, a breakpoint, the
      # breakpoints, or the stack, a Paused or +nil+ of a target running.
      #
      # @param reader [Reader]
      # @return [Array(Symbol, Object)]
      def self.debugged(reader)
        what = code(reader, ANSWERS, "no Debugged answers")
        value = case what
                when :connection then reader.u64
                when :breakpoint then breakpoint(reader)
                when :breakpoints then reader.counted { breakpoint(reader) }
                else reader.flag ? pause(reader) : nil
                end
        [what, value]
      end

      # An Event's body.
      #
      # @param reader [Reader]
      # @return [Debug::Event]
      def self.event(reader)
        kind = code(reader, EVENTS, "no debugger's event is")
        Debug::Event.new(kind:, paused: kind == :paused ? pause(reader) : nil)
      end

      # A breakpoint: number u32, schema, name, line u32, then its
      # condition if its flag says it has one.
      #
      # @param reader [Reader]
      # @return [Debug::Breakpoint]
      def self.breakpoint(reader)
        Debug::Breakpoint.new(number: reader.u32, schema: reader.str, name: reader.str, line: reader.u32,
                              condition: reader.flag ? reader.str : nil)
      end

      # A pause: its reason, a breakpoint's number u32 if one, then its
      # frames, the outermost first.
      #
      # @param reader [Reader]
      # @return [Debug::Paused]
      def self.pause(reader)
        reason = code(reader, REASONS, "no pause is for the reason")
        number = reason == :breakpoint ? reader.u32 : nil
        Debug::Paused.new(reason:, breakpoint: number, frames: reader.counted { frame(reader) })
      end

      # A frame: its origin if it has one, visible flag, its place if
      # given, its line and column if given, then its parameters,
      # variables and cursors.
      #
      # @param reader [Reader]
      # @return [Debug::Frame]
      def self.frame(reader)
        origin = reader.flag ? origin(reader) : nil
        visible = reader.flag
        place = reader.flag ? reader.u64 : nil
        line, column = reader.flag ? [reader.u32, reader.u32] : [nil, nil]
        Debug::Frame.new(origin:, visible:, place:, line:, column:, parameters: reader.counted { named(reader) },
                         variables: reader.counted { named(reader) }, cursors: reader.counted { cursor(reader) })
      end

      # A frame's routine: kind u8, its specific schema and name, then its
      # schema and name.
      #
      # @param reader [Reader]
      # @return [Debug::Origin]
      def self.origin(reader)
        Debug::Origin.new(kind: code(reader, Debug::KINDS.invert, "no routine is of the kind"),
                          specific_schema: reader.str, specific_name: reader.str, schema: reader.str, name: reader.str)
      end

      # A parameter or variable: name, data type as SQL writes it, value.
      #
      # @param reader [Reader]
      # @return [Debug::Named]
      def self.named(reader) = Debug::Named.new(name: reader.str, type: reader.str, value: ValueReader.read(reader))

      # A cursor: name, open flag, query.
      #
      # @param reader [Reader]
      # @return [Debug::Cursor]
      def self.cursor(reader) = Debug::Cursor.new(name: reader.str, open: reader.flag, query: reader.str)

      # The meaning of the next u8, a code of +codes+; another fails the
      # connection, as +none+ says.
      #
      # @param reader [Reader]
      # @param codes [Hash{Integer => Symbol}]
      # @param none [String]
      # @return [Symbol]
      def self.code(reader, codes, none)
        byte = reader.u8
        codes.fetch(byte) { raise reader.corrupt("#{none} of code #{byte}") }
      end
    end
  end
end
