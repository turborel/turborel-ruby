# frozen_string_literal: true

require "test_helper"
require_relative "../../support/fake_server"

module Turborel
  module Client
    # Pipelines, against a server of the test's own script.
    class PipelineTest < Minitest::Test
      include TestSupport

      GRANTED = Protocol::Capabilities::ALL - [Protocol::Capabilities::COMPRESSION]

      # Runs +script+ after login, then reads Terminate; gives the
      # connection and the server, which gives the frames read.
      def scripted(&)
        server = FakeServer.new do |peer|
          peer.frame
          peer.ready(GRANTED)
          frames = []
          yield(peer, frames)
          frames << peer.frame
          frames
        end
        [Client.connect_to(server.target, user: "ann", mechanism: Trust.new), server]
      end

      def outcome(piped) = piped.skipped ? :skipped : (piped.failed&.sqlstate || piped.done.sqlstate)

      # Verifies: [PROTOCOL Requests] requests sent before the last is
      # answered, the replies read in turn, in order; a failure its
      # request's own, the requests after it run.
      def test_requests_run_in_turn
        connection, server = scripted do |peer, frames|
          3.times { frames << peer.frame }
          peer.complete
          peer.error(-201, "23000", "duplicate")
          peer.complete(100, "02000")
        end
        statement = Statement.new(number: 4, parameters: [], columns: [])
        outcomes = connection.pipeline.query("INSERT 1").execute(statement, [1]).query("DELETE NONE").run

        assert_equal(%w[00000 23000 02000], outcomes.map { outcome(_1) })
        connection.terminate
        frames = server.join

        assert_equal ["Q".ord, "E".ord, "Q".ord], frames.first(3).map(&:first)
      end

      # Verifies: [CLIENT Pipelines] queued queries and executions, one
      # outcome each, a query's rows among them; under autocommit each its
      # own transaction; requests written a window of 64 KiB at a time.
      def test_windows_and_autocommit
        long = "x" * Pipeline::PIPELINE_WINDOW
        connection, server = scripted do |peer, frames|
          frames << peer.frame
          peer.complete
          frames << peer.frame
          peer.description("N")
          peer.rows([1])
          peer.complete
        end
        connection.autocommit = true
        pipeline = connection.pipeline.query(long).query("SELECT N")

        assert_equal [2, false], [pipeline.size, pipeline.empty?]
        first, second = pipeline.run

        assert_equal ["00000", [[1]]], [first.done.sqlstate, second.done.rows]
        connection.terminate
        query, = server.join

        assert_equal Protocol::Requests.query(long, ends: true), Protocol::Frame.encode(*query)
        assert_empty connection.pipeline
      end

      # Verifies: [CLIENT Pipelines] skip on error: a savepoint before each
      # request but the first; the requests after a failure rolled back to
      # the savepoint after it and skipped; the first savepoint released;
      # under autocommit, of a batch that began none, committed as it ends.
      def test_skip_on_error
        connection, server = scripted do |peer, frames|
          5.times { frames << peer.frame }
          peer.complete
          peer.complete
          peer.error(-201, "23000", "duplicate")
          peer.complete
          peer.complete
          3.times do
            frames << peer.frame
            peer.complete
          end
        end
        connection.autocommit = true
        outcomes = connection.pipeline.on_error(:skip).query("A").query("B").query("C").run

        assert_equal(["00000", "23000", :skipped], outcomes.map { outcome(_1) })
        connection.terminate
        frames = server.join
        texts = frames.first(8).map { |_, body| Protocol::Reader.new(body, "query").str }

        assert_equal ["A", "SAVEPOINT TURBOREL_PIPELINE_1", "B", "SAVEPOINT TURBOREL_PIPELINE_2", "C",
                      "ROLLBACK TO SAVEPOINT TURBOREL_PIPELINE_2", "RELEASE SAVEPOINT TURBOREL_PIPELINE_1", "COMMIT"],
                     texts
      end

      # Verifies: [CLIENT Pipelines] run fails if the connection is lost
      # (08006); a choice other than continue and skip refused.
      def test_a_lost_connection_fails_the_run
        connection, server = scripted do |peer, frames|
          2.times { frames << peer.frame }
          peer.complete
          peer.error(-919, "08006", "gone")
        end

        assert_fails { connection.pipeline.query("A").query("B").run }
        assert_fails(MISUSED) { connection.pipeline.on_error(:sometimes) }
        connection.instance_variable_get(:@stream).close
        server.join
      end

      # Verifies: [CLIENT Pipelines] skip on error across windows: a window
      # after the failure never sent, each request of it skipped, nothing to
      # undo; a batch with no failure releasing its first savepoint and not
      # committing outside autocommit; an execution of a query giving its
      # rows.
      def test_skip_across_windows
        long = "x" * Pipeline::PIPELINE_WINDOW
        connection, server = scripted do |peer, frames|
          frames << peer.frame
          peer.error(-201, "23000", "duplicate")
          3.times { frames << peer.frame }
          peer.complete
          peer.complete
          peer.rows([5])
          peer.complete
          frames << peer.frame
          peer.complete
        end
        outcomes = connection.pipeline.on_error(:skip).query(long).query("never sent").run

        assert_equal(["23000", :skipped], outcomes.map { outcome(_1) })
        statement = Statement.new(number: 1, parameters: [],
                                  columns: [Column.new(name: "N", type: nil, not_null: false)])
        kept = connection.pipeline.on_error(:skip).query("A").execute(statement).run

        assert_equal ["00000", [[5]]], [kept.first.done.sqlstate, kept.last.done.rows]
        connection.terminate
        texts = server.join.drop(1).first(4).values_at(0, 1, 3).map { |_, body| Protocol::Reader.new(body, "query").str }

        assert_equal ["A", "SAVEPOINT TURBOREL_PIPELINE_1", "RELEASE SAVEPOINT TURBOREL_PIPELINE_1"], texts
      end

      # Verifies: [CLIENT Pipelines] run fails, giving no outcome, if a
      # skipping batch's requests cannot be undone: the failure of its
      # ROLLBACK TO SAVEPOINT.
      def test_skip_that_cannot_be_undone
        connection, server = scripted do |peer, frames|
          5.times { frames << peer.frame }
          peer.complete
          peer.complete
          peer.error(-201, "23000", "duplicate")
          peer.complete
          peer.complete
          frames << peer.frame
          peer.error(-913, "40001", "the savepoint is gone")
        end
        refused = assert_fails([-913, "40001"]) do
          connection.pipeline.on_error(:skip).query("A").query("B").query("C").run
        end

        assert_equal "the savepoint is gone", refused.message
        connection.terminate

        assert_equal "ROLLBACK TO SAVEPOINT TURBOREL_PIPELINE_2",
                     Protocol::Reader.new(server.join.fetch(5).last, "query").str
      end
    end
  end
end
