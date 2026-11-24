# frozen_string_literal: true

require "socket"
require "test_helper"
require_relative "../../support/fake_server"

module Turborel
  module Client
    # The routine debugger against a server of the test's own script.
    class DebuggingTest < Minitest::Test
      include TestSupport

      DEBUGGER = [Protocol::Capabilities::DEBUGGER].freeze

      def connect(server) = Client.connect_to(server.target, user: "ann", mechanism: Trust.new)

      # An Event of +code+, with no pause.
      def event(peer, code) = peer.reply("W", writer.u8(code))

      # A column N of BOOLEAN, and a row of the byte +byte+ for it.
      def truth(peer, byte)
        peer.reply("D", writer.u32(1).flag(true).str("N").raw("\x0E".b).flag(false))
        peer.reply("B", writer.u32(1).u32(1).u8(14).u8(byte))
      end

      # Verifies: [PROTOCOL Event 'W'] an Event read wherever a reply is
      # read, among a request's replies and among those read past after a
      # value not taken, kept, never ending the request.
      # Verifies: [CLIENT Debugging routines] debug_wait gives the events
      # kept first, in order, then waits at most its timeout, giving nil if
      # none came; detaching drops those kept.
      def test_events_kept_among_replies
        server = FakeServer.new do |peer|
          peer.frame
          peer.ready(DEBUGGER)
          peer.frame
          truth(peer, 2)
          event(peer, 2)
          peer.complete
          peer.frame
          event(peer, 1)
          peer.complete(100, "02000")
          peer.frame => [_, body]
          event(peer, 3)
          peer.reply("V", writer.u8(0).u64(7))
          peer.frame
          peer.complete
          peer.frame
          body
        end
        connection = connect(server)

        assert_fails(CORRUPT) { connection.query("SELECT N FROM T") }
        assert_equal "02000", connection.query("DELETE FROM T").sqlstate
        assert_equal [:cancelled, :timed_out, nil], Array.new(3) { connection.debug_wait(0.05)&.kind }
        assert_equal 7, connection.debug_id
        connection.debug_detach

        assert_nil connection.debug_wait(0.05)
        connection.terminate

        assert_equal "\x00".b, server.join
      end

      # Verifies: [PROTOCOL Debug 'V'] each Debug request encoded and its
      # answer read: a breakpoint with a condition, the breakpoints, a
      # stack of a target running; Clear, Resume and Interrupt answered
      # by a Complete; a Debugged of another answer than asked for loses
      # the connection.
      def test_requests_and_their_answers
        breakpoint = writer.u32(2).str("S").str("F_1").u32(3).flag(true).str("X > 1")
        server = FakeServer.new do |peer|
          peer.frame
          peer.ready(DEBUGGER)
          sent = []
          sent << peer.frame
          peer.reply("V", writer.u8(1).raw(breakpoint.to_s))
          sent << peer.frame
          peer.reply("V", writer.u8(2).u32(1).raw(breakpoint.to_s))
          sent << peer.frame
          peer.reply("V", writer.u8(3).flag(false))
          3.times do
            sent << peer.frame
            peer.complete
          end
          sent << peer.frame
          peer.reply("V", writer.u8(0).u64(1))
          peer.rest
          sent
        end
        connection = connect(server)
        set = connection.debug_break(:function, "F", 3, schema: "S", condition: "X > 1")

        assert_equal [2, "S", "F_1", 3, "X > 1"], set.to_h.values
        assert_equal [[set], nil], [connection.debug_breakpoints, connection.debug_stack]
        connection.debug_clear(2)
        connection.debug_resume(:out)
        connection.debug_interrupt
        assert_fails { connection.debug_stack }
        assert_predicate connection, :lost?
        sent = server.join.map { |kind, body| [kind.chr, body.unpack1("H*")] }

        assert_equal [%w[V 03010100000053010000004603000000010500000058203e2031], %w[V 05], %w[V 08],
                      %w[V 0402000000], %w[V 0602], %w[V 07], %w[V 08]], sent
      end

      # Verifies: [CLIENT Debugging routines] debug_wait takes a Notice
      # sent unasked, giving nil; raises an Error, the session kept; loses
      # the connection on a reply that answers no request, or the server's
      # close.
      def test_waits_that_end_otherwise
        server = FakeServer.new do |peer|
          peer.frame
          peer.ready(DEBUGGER)
          peer.notice("01000")
          peer.error(-104, "42000", "no")
          event(peer, 3)
          peer.reply("G")
        end
        connection = connect(server)

        assert_nil connection.debug_wait(5)
        assert_fails([-104, "42000"]) { connection.debug_wait(5) }
        assert_equal [["01000"], :ended], [connection.take_notices.map(&:sqlstate), connection.debug_wait&.kind]
        assert_fails { connection.debug_wait(5) }
        assert_predicate connection, :lost?
        server.join
        closed = FakeServer.new do |peer|
          peer.frame
          peer.ready(DEBUGGER)
        end
        connection = connect(closed)
        closed.join

        assert_fails { connection.debug_wait(5) }
        assert_predicate connection, :lost?
      end

      # Verifies: [PROTOCOL Capabilities] debugger asked for by default; not
      # granted, a Debug request, or a wait, is a connection failure,
      # nothing sent.
      # Verifies: [CLIENT Debugging routines] a kind of routine, or a way to
      # go on, of no code is the program's misuse.
      def test_not_granted_and_misused
        server = FakeServer.new do |peer|
          peer.frame => [_, hello]
          peer.ready
          peer.frame
          hello
        end
        connection = connect(server)

        assert_fails { connection.debug_id }
        assert_fails { connection.debug_wait(1) }
        assert_fails(MISUSED) { connection.debug_break(:view, "V", 1) }
        assert_fails(MISUSED) { connection.debug_resume(:sideways) }
        refute_predicate connection, :lost?
        connection.terminate

        assert_includes server.join, "debugger"
      end

      # Verifies: [CLIENT Debugging routines] a connection over a stream
      # given to open waits for an event without limit, a timeout refused
      # with the connection kept; Terminate reads past an Event.
      def test_a_stream_given_to_open
        server = FakeServer.new do |peer|
          peer.frame
          peer.ready(DEBUGGER)
          event(peer, 3)
          peer.frame
          event(peer, 2)
        end
        connection = Connection.open(TCPSocket.new("127.0.0.1", server.port), user: "ann", mechanism: Trust.new)

        assert_fails { connection.debug_wait(1) }
        refute_predicate connection, :lost?
        assert_equal :ended, connection.debug_wait.kind
        connection.terminate
        server.join
      end
    end
  end
end
