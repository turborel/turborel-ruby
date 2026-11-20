# frozen_string_literal: true

require "test_helper"
require_relative "../../support/fake_server"

module Turborel
  module Client
    # A connection's statements, against a server of the test's own script.
    class StatementsTest < Minitest::Test
      include TestSupport

      # A sink that keeps what it is given.
      class Kept
        attr_reader :given

        def initialize = @given = []

        def columns(columns) = @given << columns.map(&:name)

        def rows(rows) = @given << rows
      end

      # Runs +script+ after login granting +granted+, then reads Terminate;
      # gives the connection to the block and the frames the server read
      # after login, Terminate's but last.
      def scripted(granted = Protocol::Capabilities::ALL, &)
        server = FakeServer.new do |peer|
          peer.frame
          peer.ready(granted)
          frames = []
          yield(peer, frames)
          frames << peer.frame.first
          frames
        end
        connection = Client.connect_to(server.target, user: "ann", mechanism: Trust.new)
        [connection, server]
      end

      # Verifies: [PROTOCOL Query 'Q'] a query answered by Description, Rows
      # and Complete, another statement by Complete, a failure by Error;
      # Query carries the SQL text and ends, with no attributes unless set.
      def test_queries_and_their_outcomes
        connection, server = scripted do |peer, frames|
          frames << peer.frame
          peer.description("N")
          peer.rows([1], [2])
          peer.rows([3])
          peer.complete(0, "00000", active: true)
          frames << peer.frame
          peer.complete(100, "02000", active: true)
          frames << peer.frame
          peer.error(-103, "2A000", "table ANN.NOPE is not defined", active: true)
        end
        rows = connection.query("SELECT N FROM T")

        assert_equal [["N"], [[1], [2], [3]]], [rows.columns.map(&:name), rows.rows]
        assert_predicate connection, :in_transaction?
        assert_equal([100, "02000"], connection.query("DELETE FROM T").then { [_1.sqlcode, _1.sqlstate] })
        assert_fails([-103, "2A000"]) { connection.query("SELECT * FROM NOPE") }
        refute_predicate connection, :lost?
        connection.terminate

        assert_equal ["Q".ord, Protocol::Writer.new.str("SELECT N FROM T").flag(false).to_s], server.join.first
      end

      # Verifies: [PROTOCOL Conversations] a statement under autocommit is
      # one Query with ends set; a failing commit's Error comes in place of the
      # Complete, the transaction rolled back.
      def test_autocommit_sets_ends
        connection, server = scripted do |peer, frames|
          frames << peer.frame
          peer.complete
          frames << peer.frame
          peer.error(-913, "40002", "a deferred constraint is not satisfied")
        end
        connection.autocommit = true

        assert connection.autocommit
        connection.query("INSERT INTO T VALUES (1)")
        assert_fails([-913, "40002"]) { connection.query("INSERT INTO D VALUES (-1)") }
        refute_predicate connection, :in_transaction?
        connection.terminate
        query, = server.join

        assert_equal Protocol::Writer.new.str("INSERT INTO T VALUES (1)").flag(true).to_s, query.last
      end

      # Verifies: [CLIENT Running statements] a query's rows given to a sink
      # a batch at a time, as they come; another statement's completion as
      # it is.
      def test_query_into_a_sink
        connection, = scripted do |peer, frames|
          frames << peer.frame
          peer.description("N")
          peer.rows([1], [2])
          peer.rows([3])
          peer.complete
          frames << peer.frame
          peer.complete
        end
        sink = Kept.new

        assert_equal 3, connection.query_into("SELECT N FROM T", sink)
        assert_equal [["N"], [[1], [2]], [[3]]], sink.given
        assert_equal "00000", connection.query_into("COMMIT", sink).sqlstate
        connection.terminate
      end

      # Verifies: [PROTOCOL Prepare 'P'] Prepare carries the client's number
      # for the statement, from 0 up, and its text; Prepared gives its
      # parameters and columns; Execute of a statement with no columns is
      # answered by Complete, of a query by its rows.
      def test_prepare_and_execute
        connection, server = scripted do |peer, frames|
          frames << peer.frame
          peer.prepared(0, 2)
          frames << peer.frame
          peer.complete
          frames << peer.frame
          peer.prepared(1, 1, "N")
          frames << peer.frame
          peer.rows([4])
          peer.complete
        end
        insert = connection.prepare("INSERT INTO T VALUES (?, ?)")

        assert_equal [0, 2, []], [insert.number, insert.parameters.size, insert.columns]
        assert_equal 0, connection.execute(insert, [1, 2]).sqlcode
        query = connection.prepare("SELECT N FROM T WHERE N = ?")

        assert_equal [[4]], connection.execute(query, [4]).rows
        connection.terminate
        frames = server.join

        assert_equal ["P".ord, Protocol::Writer.new.u32(0).str("INSERT INTO T VALUES (?, ?)").to_s], frames[0]
        assert_equal Protocol::Requests.execute(1, [4], rows: 0, ends: false), Protocol::Frame.encode(*frames[3])
      end

      # Verifies: [PROTOCOL Execute 'E'] a cursor opened with at most so
      # many rows, Suspended if it has more; Fetch gives the next, Complete
      # once none are left; Close and Deallocate answered by Complete.
      def test_cursors
        connection, = scripted do |peer, frames|
          4.times do |step|
            frames << peer.frame
            step.zero? ? peer.prepared(0, 0, "N") : peer.rows([step])
            step.between?(1, 2) ? peer.reply("S") : (peer.complete unless step.zero?)
          end
          2.times do
            frames << peer.frame
            peer.complete
          end
        end
        statement = connection.prepare("SELECT N FROM T")

        assert_equal Batch.new(rows: [[1]], more: true), connection.open_cursor(statement, [], 1)
        assert_equal Batch.new(rows: [[2]], more: true), connection.fetch(statement, 1)
        assert_equal Batch.new(rows: [[3]], more: false), connection.fetch(statement)
        assert_nil connection.close(statement)
        assert_nil connection.deallocate(statement)
        connection.terminate
      end

      # Verifies: [PROTOCOL Close 'C'] Close of a statement's cursor,
      # answered by Complete, or by Error if it is not open, the
      # connection kept.
      def test_close
        connection, server = scripted do |peer, frames|
          frames << peer.frame
          peer.complete
          frames << peer.frame
          peer.error(-501, "24000", "the cursor is not open")
        end
        statement = Statement.new(number: 3, parameters: [], columns: [])

        assert_nil connection.close(statement, cursor: 1)
        assert_fails([-501, "24000"]) { connection.close(statement) }
        connection.terminate

        assert_equal Protocol::Requests.close(3, cursor: 1), Protocol::Frame.encode(*server.join.first)
      end

      # Verifies: [PROTOCOL Deallocate 'D'] Deallocate of a statement,
      # answered by Complete; none such fails with 26000, the connection
      # kept.
      def test_deallocate
        connection, server = scripted do |peer, frames|
          frames << peer.frame
          peer.complete
          frames << peer.frame
          peer.error(-921, "26000", "there is no statement 3")
        end
        statement = Statement.new(number: 3, parameters: [], columns: [])

        assert_nil connection.deallocate(statement)
        assert_fails([-921, "26000"]) { connection.deallocate(statement) }
        connection.terminate

        assert_equal Protocol::Requests.deallocate(3), Protocol::Frame.encode(*server.join.first)
      end

      # Verifies: [PROTOCOL Describe 'Y'] a prepared statement described
      # again, answered by Prepared; an open cursor's columns, by
      # Description; numbered cursors carry tag 3.
      def test_describe_and_numbered_cursors
        connection, server = scripted do |peer, frames|
          frames << peer.frame
          peer.prepared(0, 0, "N")
          frames << peer.frame
          peer.prepared(0, 0, "N")
          frames << peer.frame
          peer.description("N")
          frames << peer.frame
          peer.rows([1])
          peer.reply("S")
        end
        statement = connection.prepare("SELECT N FROM T")

        assert_equal statement, connection.describe(statement)
        assert_equal ["N"], connection.describe_cursor(statement, 2).map(&:name)
        assert_predicate connection.open_cursor_numbered(statement, 2), :more
        connection.terminate
        frames = server.join

        assert_equal Protocol::Requests.describe_cursor(0, 2), Protocol::Frame.encode(*frames[2])
        assert_equal Protocol::Requests.execute(0, [], rows: 0, ends: false, tail: { cursor: 2 }),
                     Protocol::Frame.encode(*frames[3])
      end

      # Verifies: [CLIENT What a connection asks for] a method needing a
      # capability not granted fails before it sends anything, the
      # connection kept: a numbered cursor without cursors, describe without
      # describe.
      def test_methods_needing_a_capability_not_granted
        connection, server = scripted([]) do |peer, frames|
          frames << peer.frame
          peer.prepared(0, 0, "N")
        end
        statement = connection.prepare("SELECT N FROM T")

        [-> { connection.open_cursor_numbered(statement, 1) }, -> { connection.fetch(statement, cursor: 1) },
         -> { connection.close(statement, cursor: 1) }, -> { connection.describe(statement) },
         -> { connection.describe_cursor(statement) }].each { |refused| assert_fails(&refused) }
        refute_predicate connection, :lost?
        connection.terminate

        assert_equal(["P".ord, "X".ord], server.join.map { _1.is_a?(Array) ? _1.first : _1 })
      end

      # Verifies: [PROTOCOL Requests] a reply out of turn, as Pong to a
      # Query, loses the connection; a statement's Error of class 08 does
      # too.
      def test_replies_out_of_turn_lose_the_connection
        connection, server = scripted do |peer, frames|
          frames << peer.frame
          peer.reply("G")
        end
        error = assert_fails { connection.query("VALUES 1") }

        assert_match(/Pong out of turn/, error.message)
        assert_predicate connection, :lost?
        assert_fails { connection.query("VALUES 1") }
        connection.instance_variable_get(:@stream).close
        server.join
      end
    end
  end
end
