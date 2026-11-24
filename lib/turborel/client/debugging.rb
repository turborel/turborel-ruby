# frozen_string_literal: true

module Turborel
  module Client
    # *(extension)* The routine debugger [CLIENT Debugging routines]: a
    # connection granted +debugger+ attaches to the session of another
    # connection, by that one's ID, sets breakpoints in the routines and
    # triggers its user may debug, and drives that session as it pauses,
    # step by step, reading its call stack, parameters, variables and
    # cursors [PROTOCOL Debug 'V']. What it hears of its target, a
    # Debug::Event, comes unasked between its requests, and is kept until
    # debug_wait reads it.
    #
    # Two connections: the target runs its statements as ever, and the
    # debugger waits for its events beside it, often on another thread.
    # Each refusal keeps the session: SQLSTATE 08003 of a connection not
    # seen, 42000 (SQLCODE -104) of a routine its user holds no DEBUG on,
    # TBD01 (SQLCODE -910) of a request the target's state does not allow.
    module Debugging
      # This connection's ID, as INFORMATION_SCHEMA.CONNECTIONS shows it:
      # what a debugger attaches to its session by.
      #
      # @return [Integer]
      # @raise [Error] a connection failure: debugger not granted, or the
      #   server gone
      def debug_id = debugged(Protocol::Requests.debug(Protocol::Requests::DEBUG_IDENTIFY), :connection)

      # Attaches this connection as the debugger of the session of the
      # connection +id+: one of its own user's, or any if its user is the
      # database's owner or holds MONITOR.
      #
      # @param id [Integer]
      # @return [void]
      # @raise [Error] SQLSTATE 08003 if no connection of that ID is served
      #   whose session this one may debug; TBD01 if this connection is
      #   attached already, or the session is this one's, or has a
      #   debugger already
      def debug_attach(id) = debug_done(Protocol::Requests.debug_attach(id))

      # Detaches this connection: its breakpoints gone, its target, if
      # paused, going on, the events kept of it dropped.
      #
      # @return [void]
      # @raise [Error] SQLSTATE TBD01 if it is attached to none
      def debug_detach
        events_kept.clear
        debug_done(Protocol::Requests.debug(Protocol::Requests::DEBUG_DETACH))
      end

      # A breakpoint at line +line+, from 1, of the text of the routine of
      # +kind+ named +name+, its specific name or, if it is the one
      # routine of that kind so named, its name; or of the trigger +name+.
      # An empty +schema+ is the session's default. The target pauses at
      # each statement that begins on that line, where +condition+, a
      # <search condition> over the frame's parameters and variables, is
      # true if given.
      #
      # @param kind [Symbol] +:procedure+, +:function+ or +:trigger+
      # @param name [String]
      # @param line [Integer]
      # @param schema [String]
      # @param condition [String, nil]
      # @return [Debug::Breakpoint] the breakpoint set, its routine named
      #   by its specific name
      # @raise [Error] SQLCODE -103 if there is no such routine or line,
      #   -104 if the user holds no DEBUG on it; TBD01 if this connection
      #   is attached to none
      def debug_break(kind, name, line, schema: "", condition: nil)
        debugged(Protocol::Requests.debug_break(kind, schema, name, line, condition), :breakpoint)
      end

      # Clears the breakpoint +number+.
      #
      # @param number [Integer]
      # @return [void]
      # @raise [Error] SQLSTATE TBD01 if there is none of that number, or
      #   this connection is attached to none
      def debug_clear(number) = debug_done(Protocol::Requests.debug_clear(number))

      # The breakpoints set, in the order they were set.
      #
      # @return [Array<Debug::Breakpoint>]
      # @raise [Error] SQLSTATE TBD01 if this connection is attached to none
      def debug_breakpoints
        debugged(Protocol::Requests.debug(Protocol::Requests::DEBUG_BREAKPOINTS), :breakpoints)
      end

      # Tells the paused target to go on as +action+ says: +:into+ to its
      # next statement, within a routine it invokes too; +:over+ to the
      # next of this frame or one it returns to; +:out+ to the next of the
      # frame it returns to; +:continue+ to a breakpoint.
      #
      # @param action [Symbol]
      # @return [void]
      # @raise [Error] SQLSTATE TBD01 if the target is not paused, or this
      #   connection is attached to none
      def debug_resume(action) = debug_done(Protocol::Requests.debug_resume(action))

      # Tells the running target to pause at the next statement it runs
      # of a routine the debugger may debug.
      #
      # @return [void]
      # @raise [Error] SQLSTATE TBD01 if this connection is attached to none
      def debug_interrupt = debug_done(Protocol::Requests.debug(Protocol::Requests::DEBUG_INTERRUPT))

      # The target's pause, with its call stack, the outermost frame
      # first; +nil+ while it runs.
      #
      # @return [Debug::Paused, nil]
      # @raise [Error] SQLSTATE TBD01 if this connection is attached to none
      def debug_stack = debugged(Protocol::Requests.debug(Protocol::Requests::DEBUG_STACK), :stack)

      # The next event of the session this connection debugs not yet read:
      # one kept, else the next the server sends, waited for at most
      # +timeout+ seconds, without limit if +nil+; +nil+ if none came. A
      # connection over a stream given to open, or a named pipe, waits
      # only without limit. It is read between requests, never while one
      # is answered.
      #
      # @param timeout [Numeric, nil]
      # @return [Debug::Event, nil]
      # @raise [Error] a connection failure: debugger not granted, a
      #   +timeout+ of a stream that cannot be bounded, the server gone, or
      #   a reply where an event was waited for
      def debug_wait(timeout = nil)
        needs(false, Protocol::Capabilities::DEBUGGER)
        kept = events_kept.shift
        return kept if kept
        return nil unless arrives_within?(timeout)

        reply = next_reply(:one)
        case reply
        when Debug::Event then reply
        when Protocol::Replies::ErrorReply then raise failed(reply.failure)
        when Protocol::Replies::Notice, Protocol::Replies::Status
          took(reply)
          nil
        else raise lose("the server sent #{reply.class.name.to_s.split("::").last} answering no request")
        end
      end

      private

      # The value of Debugged of +what+ that answers the Debug request
      # +frame+.
      def debugged(frame, what)
        needs(false, Protocol::Capabilities::DEBUGGER)
        send_frame(frame)
        reply = expect(Protocol::Replies::Debugged)
        raise lose("the server sent no Debugged of #{what}") unless reply.what == what

        reply.value
      end

      # Sends the Debug request +frame+ and reads its completion.
      def debug_done(frame)
        needs(false, Protocol::Capabilities::DEBUGGER)
        send_frame(frame)
        completion_reply
        nil
      end

      # Whether a frame begins to arrive within +timeout+ seconds, without
      # limit if +nil+, nothing of it read.
      def arrives_within?(timeout)
        stream = @stream
        unless timeout.nil? || stream.bounded?
          raise Error.connection_failure("a stream that cannot be bounded waits without limit")
        end

        begin
          stream.arrives_within?(timeout)
        rescue Error => e
          raise lost_by(e)
        end
      end
    end
  end
end
