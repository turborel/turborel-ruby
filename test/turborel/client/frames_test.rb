# frozen_string_literal: true

require "socket"
require "test_helper"
require_relative "../../support/fake_server"

module Turborel
  module Client
    # Replies the driver cannot take, against a server of the test's own
    # script.
    class FramesTest < Minitest::Test
      include TestSupport

      def connect(server) = Client.connect_to(server.target, user: "ann", mechanism: Trust.new)

      # A column N of BOOLEAN, as a Description writes it.
      def truth_column = Protocol::Writer.new.u32(1).flag(true).str("N").raw("\x0E".b).flag(false)

      # A Rows frame of one row of a truth byte +byte+.
      def truth_rows(byte) = Protocol::Writer.new.u32(1).u32(1).u8(14).u8(byte)

      # Verifies: [PROTOCOL Values and fields] a value whose body its reader
      # cannot take leaves its frame read whole and the stream in step: the
      # request fails with the value's error, TB916, not of class 08, once
      # the rest of its replies are read past to the last, a Notice among
      # them taken, another that cannot be taken passed over; the next
      # request takes its own replies.
      # Verifies: [CLIENT Running statements] the connection goes on.
      def test_a_value_not_taken_fails_its_request_alone
        server = FakeServer.new do |peer|
          peer.frame
          peer.ready
          peer.frame
          peer.reply("D", truth_column)
          peer.reply("B", truth_rows(2))
          peer.notice("01000", "noted")
          peer.reply("B", truth_rows(3))
          peer.reply("B", truth_rows(1))
          peer.complete
          peer.frame
          peer.complete(100, "02000")
          peer.frame
        end
        connection = connect(server)
        refused = assert_fails(CORRUPT) { connection.query("SELECT N FROM T") }

        assert_match(/not a truth value/, refused.message)
        refute_predicate connection, :lost?
        assert_equal ["02000", ["01000"]], [connection.query("DELETE FROM T").sqlstate,
                                            connection.take_notices.map(&:sqlstate)]
        connection.terminate
        server.join
      end

      # Verifies: [PROTOCOL Values and fields] a Complete whose condition
      # cannot be read taken by its head, its tag 5 saying more replies
      # follow, which are read past to the last, noted as the session's
      # state; a malformed frame, bytes left after its last field, loses
      # the connection (08006).
      def test_a_condition_not_taken_and_a_frame_malformed
        server = FakeServer.new do |peer|
          peer.frame
          peer.ready(Protocol::Capabilities::ALL - [Protocol::Capabilities::COMPRESSION])
          peer.frame
          head = Protocol::Writer.new.u32(0).str("01000").flag(true).u8(5).u8(17).u32(1).bytes("\x01".b)
          peer.reply("K", head)
          peer.complete
          peer.frame
          peer.reply("K", Protocol::Writer.new.u32(0).str("00000").flag(false).u8(0))
          peer.rest
        end
        connection = connect(server)

        ran = connection.query_many("UPDATE T SET N = 1; COMMIT")

        assert_equal [[], CORRUPT], [ran.outcomes, [ran.failure.sqlcode, ran.failure.sqlstate]]
        assert_equal ["00000", false], [connection.completion.sqlstate, connection.in_transaction?]
        assert_fails { connection.query("COMMIT") }
        assert_predicate connection, :lost?
        server.join
      end

      # Verifies: [PROTOCOL Values and fields] a Describe of a cursor,
      # answered by a Description alone, fails with its value's error,
      # nothing after it waited for.
      def test_a_description_alone
        server = FakeServer.new do |peer|
          peer.frame
          peer.ready(Protocol::Capabilities::ALL - [Protocol::Capabilities::COMPRESSION])
          peer.frame
          peer.reply("D", Protocol::Writer.new.u32(1).flag(true).str("C").raw("\x01\x0A\x00\x00\x00\x02".b).flag(false))
          peer.frame
          peer.complete
          peer.frame
        end
        connection = connect(server)
        statement = Statement.new(number: 1, parameters: [], columns: [])

        assert_fails(CORRUPT) { connection.describe_cursor(statement) }
        assert_equal "00000", connection.query("COMMIT").sqlstate
        connection.terminate
        server.join
      end

      # Verifies: [CLIENT Connecting] Terminate reads past a Notice or a
      # Status before the Error it ends with, and gives that Error.
      def test_terminate_reads_past_to_its_error
        server = FakeServer.new do |peer|
          peer.frame
          peer.ready
          peer.frame
          peer.notice("01T01", "rolled back")
          peer.status("SCHEMA", "ANN")
          peer.error(-913, "40002", "a deferred constraint is not satisfied")
        end

        assert_fails([-913, "40002"]) { connect(server).terminate }
        server.join
      end

      # Verifies: [CLIENT Timeouts] a stream of the program's own that bounds
      # itself, opened within Timeouts, bounded as they say: each step of
      # the login by connect, each wait after by read, which read_timeout=
      # changes as it does a connection the driver makes.
      def test_a_stream_opened_within_timeouts
        server = FakeServer.new do |peer|
          peer.frame
          peer.ready
          peer.rest
        end
        socket = TCPSocket.new("127.0.0.1", server.port)
        connection = Connection.open_within(socket, user: "ann", mechanism: Trust.new,
                                                    timeouts: Timeouts.new(connect: 5, read: 0.05))

        assert_in_delta 0.05, connection.read_timeout
        connection.read_timeout = 0.02
        assert_fails { connection.query("VALUES 1") }
        assert_predicate connection, :lost?
        server.join
      end
    end
  end
end
