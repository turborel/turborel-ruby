# frozen_string_literal: true

require "test_helper"
require_relative "../../support/fake_server"

module Turborel
  module Client
    # What a connection's session tells and how it is controlled, against a
    # server of the test's own script.
    class SessionTest < Minitest::Test
      include TestSupport

      # A Complete's tail: tag 4 the commit's position, 6 the rows, 16 the
      # values generated, 18 the server's time.
      TOLD = Protocol::Writer.new.u8(4).u64(9).u8(6).u64(3).u8(16).strs(%w[1 2]).u8(18).u64(7).u64(1).u64(2).to_s

      # A mechanism that answers each challenge by reversing it.
      class Echo < Mechanism
        def name = "echo"

        def initial = "hi".b

        def answer(challenge) = challenge.reverse
      end

      # Runs +script+ after login granting +granted+, then reads Terminate;
      # gives the connection and the server.
      def scripted(granted = Protocol::Capabilities::ALL, &)
        server = FakeServer.new do |peer|
          peer.frame
          peer.ready(granted)
          frames = []
          yield(peer, frames)
          frames << peer.frame
          frames
        end
        [Client.connect_to(server.target, user: "ann", mechanism: Trust.new), server]
      end

      # A condition of a Complete's tail 17: a failure written as bytes.
      def condition(sqlstate)
        failure = Protocol::Writer.new.i32(0).str(sqlstate).str("warned").flag(false).flag(false).flag(true).to_s
        Protocol::Writer.new.u8(17).u32(1).bytes(failure).to_s
      end

      # Verifies: [CLIENT What the server tells] a completion's rows, values
      # generated, server time and commit position; the position kept
      # until the next commit; a warning's SQLSTATE; conditions taken once.
      def test_what_the_server_tells
        connection, = scripted do |peer, frames|
          frames << peer.frame
          peer.complete(0, "00000", tail: TOLD)
          frames << peer.frame
          peer.complete(0, "01003", active: true, tail: condition("01003"))
        end
        connection.query("INSERT INTO G (V) VALUES (5), (6), (7)")

        assert_equal [3, %w[1 2], Timing.new(total: 7, queued: 1, locks: 2), 9],
                     [connection.rows_affected, connection.last_generated, connection.server_time,
                      connection.commit_position]
        connection.query("SELECT SUM(V) FROM T")

        assert_equal [9, "01003", nil], [connection.commit_position, connection.warning, connection.rows_affected]
        assert_equal ["01003"], connection.conditions.map(&:sqlstate)
        assert_equal ["01003"], connection.take_conditions.map(&:sqlstate)
        assert_empty connection.take_conditions
        connection.terminate
      end

      # Verifies: [CLIENT What the server tells] before any statement, none
      # of a completion is told.
      def test_nothing_told_before_a_statement
        connection, = scripted { nil }

        assert_equal [nil, nil, [], [], nil, []],
                     [connection.rows_affected, connection.server_time, connection.last_generated,
                      connection.conditions, connection.completion, connection.take_conditions]
        connection.terminate
      end

      # Verifies: [CLIENT What the server tells] notices go to a handler as
      # they come; with none, the last 64 are kept, the oldest dropped, and
      # taken.
      def test_notices_kept_or_handled
        connection, = scripted do |peer, frames|
          frames << peer.frame
          66.times { |i| peer.notice("01#{format("%03d", i)}") }
          peer.complete
          frames << peer.frame
          peer.notice("01ABC")
          peer.complete
        end
        connection.query("VALUES 1")
        kept = connection.take_notices

        assert_equal [64, "01002", "01065"], [kept.size, kept.first.sqlstate, kept.last.sqlstate]
        assert_empty connection.take_notices
        handled = []
        connection.notice_handler = ->(notice) { handled << notice.sqlstate }
        connection.query("VALUES 2")

        assert_equal [["01ABC"], []], [handled, connection.take_notices]
        connection.terminate
      end

      # Verifies: [PROTOCOL The tail] query attributes are sent with each
      # Query and Execute, tag 1, once granted, until set again; never a
      # tail field of a capability not granted.
      def test_query_attributes
        connection, server = scripted do |peer, frames|
          2.times do
            frames << peer.frame
            peer.complete
          end
        end
        connection.query_attributes = [%w[app reports]]

        assert_equal [%w[app reports]], connection.query_attributes
        connection.query("VALUES 1")
        connection.query_attributes = []
        connection.query("VALUES 1")
        connection.terminate
        first, second = server.join

        assert_equal Protocol::Requests.query("VALUES 1", ends: false, attributes: [%w[app reports]]),
                     Protocol::Frame.encode(*first)
        assert_equal Protocol::Requests.query("VALUES 1", ends: false), Protocol::Frame.encode(*second)
      end

      # Verifies: [PROTOCOL Conversations] a reset of a session in a
      # transaction: ping answered by Pong; Reset by its notice 01T01, a
      # Status of each setting, then Complete, no transaction active after.
      def test_ping_and_reset
        connection, = scripted do |peer, frames|
          frames << peer.frame
          peer.reply("G")
          frames << peer.frame
          peer.notice("01T01")
          peer.status("SCHEMA", "ANN")
          peer.complete
        end

        assert_nil connection.ping
        assert_nil connection.reset
        assert_equal [["01T01"], "ANN", false],
                     [connection.take_notices.map(&:sqlstate), connection.setting("SCHEMA"), connection.in_transaction?]
        connection.terminate
      end

      # Verifies: [PROTOCOL ChangeUser 'U'] ChangeUser of the user, the
      # mechanism and its first bytes, each Challenge answered, then Ready:
      # the new authorization and cancel key, no transaction active.
      def test_change_user
        connection, server = scripted do |peer, frames|
          frames << peer.frame
          peer.complete(0, "00000", active: true)
          frames << peer.frame
          peer.reply("C", Protocol::Writer.new.bytes("go"))
          frames << peer.frame
          peer.ready(Protocol::Capabilities::ALL, authorization: "BOB")
        end
        connection.query("VALUES 1")
        connection.change_user("bob", Echo.new)

        assert_equal ["BOB", false], [connection.authorization, connection.in_transaction?]
        connection.terminate
        _, change, answer = server.join

        assert_equal Protocol::Requests.change_user("bob", "echo", "hi".b), Protocol::Frame.encode(*change)
        assert_equal Protocol::Requests.answer("og"), Protocol::Frame.encode(*answer)
      end

      # Verifies: [CLIENT Controlling the session] several statements in one
      # request: each outcome until the last says no more follow, or the
      # failure that stopped the rest; a failure that loses the connection
      # is raised.
      def test_several_statements
        more = Protocol::Writer.new.u8(5).to_s
        connection, = scripted do |peer, frames|
          frames << peer.frame
          peer.complete(0, "00000", tail: more)
          peer.description("N")
          peer.rows([1])
          peer.complete(0, "00000", tail: more)
          peer.error(-201, "23000", "the key is held")
          frames << peer.frame
          peer.complete
        end
        ran = connection.query_many("INSERT INTO T VALUES (1); SELECT N FROM T; INSERT INTO T VALUES (1)")

        assert_equal [Completion, Rows], ran.outcomes.map(&:class)
        assert_equal "23000", ran.failure.sqlstate
        empty = connection.query_many("")

        assert_equal Ran.new(outcomes: [connection.completion], failure: nil), empty
        connection.terminate
      end

      # Verifies: [PROTOCOL Requests] a failure that loses the connection in
      # the midst of several statements is raised, not kept as theirs.
      def test_several_statements_losing_the_connection
        connection, server = scripted do |peer, frames|
          frames << peer.frame
          peer.error(-919, "08006", "gone")
        end

        assert_fails { connection.query_many("VALUES 1; VALUES 2") }
        assert_predicate connection, :lost?
        connection.instance_variable_get(:@stream).close
        server.join
      end
    end
  end
end
