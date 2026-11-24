# frozen_string_literal: true

module Turborel
  # *(extension)* What a connection granted +debugger+ is told of the
  # session it debugs [PROTOCOL Debugged 'V'] [PROTOCOL Event 'W']: its
  # breakpoints, its pauses with their call stacks, and what ends a pause.
  module Debug
    # The kinds of routine a breakpoint is set in, by their codes.
    KINDS = { procedure: 0, function: 1, trigger: 2 }.freeze
    # How a paused target goes on, by their codes: +:into+ to its next
    # statement in whatever frame, +:over+ to the next of this frame or
    # one it returns to, +:out+ to the next of the frame this one returns
    # to, +:continue+ to a breakpoint.
    ACTIONS = { into: 0, over: 1, out: 2, continue: 3 }.freeze

    # A breakpoint: its +number+, the +schema+ and specific +name+ of its
    # routine, or its trigger's name, its +line+ from 1, and its
    # +condition+, +nil+ if none.
    Breakpoint = Data.define(:number, :schema, :name, :line, :condition)

    # A pause of the target, at a breakpoint or at a step's end: its
    # +reason+, +:breakpoint+ or +:step+, the +breakpoint+'s number, +nil+
    # of a step, and its call stack's +frames+, the outermost first.
    Paused = Data.define(:reason, :breakpoint, :frames)

    # A frame of the call stack, a run of a routine's or a trigger's body:
    # its +origin+, +nil+ of a statement run directly; whether it is
    # +visible+, one the debugger may see into, else showing its origin
    # alone; its +place+ in characters from the beginning of the routine's
    # text, its +line+ and +column+ from 1, each +nil+ if not told; and
    # its +parameters+, +variables+ (each a Named) and +cursors+ (each a
    # Cursor). A trigger's parameters are its transition variables.
    Frame = Data.define(:origin, :visible, :place, :line, :column, :parameters, :variables, :cursors)

    # The routine of a frame: its +kind+, +:procedure+, +:function+ or
    # +:trigger+; its +specific_schema+ and +specific_name+; and its
    # +schema+ and +name+, as INFORMATION_SCHEMA.ROUTINES names them.
    Origin = Data.define(:kind, :specific_schema, :specific_name, :schema, :name)

    # A parameter or variable of a frame: its +name+, its data +type+ as
    # SQL writes it, and its +value+, as a row's value is read.
    Named = Data.define(:name, :type, :value)

    # A cursor of a frame: its +name+, whether it is +open+, and its
    # +query+.
    Cursor = Data.define(:name, :open, :query)

    # What the debugger hears of its target, unasked: +kind+ +:paused+,
    # with the Paused +paused+; +:timed_out+, paused longer than
    # DEBUGGER.PAUSE_TIMEOUT_MS, it went on by itself; +:cancelled+, its
    # statement cancelled while it was paused; or +:ended+, its session
    # ended and the debugger detached.
    Event = Data.define(:kind, :paused)

    # An event, of no pause unless paused.
    class Event
      # An event, +paused+ nil but of +:paused+.
      def initialize(kind:, paused: nil) = super
    end
  end
end
