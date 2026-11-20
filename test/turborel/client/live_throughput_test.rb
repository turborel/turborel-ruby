# frozen_string_literal: true

require "test_helper"
require_relative "../../server/live_server"

module Turborel
  module Client
    # Pipelines, pools and the SQL-agent on a live server (RULES.md
    # R-TEST-8), skipped without one.
    class LiveThroughputTest < Minitest::Test
      include TestSupport
      include LiveServer::Case

      def settings = Settings.from_uri("turborel://ann@127.0.0.1:#{server.port}/?tls_mode=disable") { nil }

      def config(**) = PoolConfig.default.with(**)

      def outcome(piped) = piped.skipped ? :skipped : (piped.failed&.sqlstate || piped.done.sqlstate)

      # Verifies: [CLIENT Pipelines] a batch of queries and executions, one
      # outcome each, a failure its own; skip on error, a batch of one
      # transaction committed as it ends under autocommit, the requests
      # after a failure undone.
      def test_pipelines
        connect do |c|
          c.query("CREATE TABLE PIPED (ID INTEGER PRIMARY KEY, NAME VARCHAR(10))")
          c.query("COMMIT")
          insert = c.prepare("INSERT INTO PIPED VALUES (?, ?)")
          outcomes = c.pipeline.query("INSERT INTO PIPED VALUES (1, 'a')").execute(insert, [2, "b"])
                      .execute(insert, [1, "dup"]).query("SELECT ID FROM PIPED ORDER BY ID").run

          assert_equal [[[1], [2]], "23000"], [outcomes.last.done.rows, outcome(outcomes[2])]
          c.query("ROLLBACK")
          c.autocommit = true
          skipped = c.pipeline.on_error(:skip).query("INSERT INTO PIPED VALUES (1, 'a')").execute(insert, [2, "b"])
                     .execute(insert, [1, "dup"]).query("INSERT INTO PIPED VALUES (3, 'c')").run

          assert_equal(["00000", "00000", "23000", :skipped], skipped.map { outcome(_1) })
          assert_equal [false, [[1], [2]]], [c.in_transaction?, c.query("SELECT ID FROM PIPED ORDER BY ID").rows]
        end
      end

      # Verifies: [CLIENT Pools] a bounded set of connections: get an idle
      # one or make one while fewer than max are made, else wait, failing
      # with 08001 past wait; a connection given back as it is released,
      # reset by Reset, autocommit off, then the reset statements, run after
      # Reset as the zone the program set is put back and the reset's own
      # kept.
      def test_a_pool
        pool = Pool.new(settings, config(max: 2, wait: 0.5, reset: ["SET TIME ZONE INTERVAL '+03:00' HOUR TO MINUTE"]))
        first = pool.get
        second = pool.get

        assert_equal [2, 0], pool.counts
        assert_fails([-919, "08001"]) { pool.get }
        first.connection.autocommit = true
        first.connection.query("SET TIME ZONE INTERVAL '+02:00' HOUR TO MINUTE")
        first.release
        first.release

        assert_equal [2, 1], pool.counts
        assert_fails(MISUSED) { first.connection }
        pool.get do |c|
          assert_equal ["+03:00", false], [c.setting("SESSION.TIME_ZONE"), c.autocommit]
        end
        second.release

        assert_equal [2, 2], pool.counts
      end

      # Verifies: [CLIENT Pools] one idle past idle_timeout, or past its
      # lifetime, closed as get meets it, another made; one beyond max_idle
      # closed as it comes back; a connection lost closed, never handed out
      # again.
      def test_pool_limits
        pool = Pool.new(settings, config(max: 3, max_idle: 1, idle_timeout: 0.05, max_lifetime: 30))
        held = [pool.get, pool.get]
        held.each(&:release)

        assert_equal [1, 1], pool.counts
        sleep 0.1
        pool.get(&:ping)

        assert_equal [1, 1], pool.counts
        lost = pool.get
        lost.connection.abandon
        lost.release

        assert_equal [0, 0], pool.counts
        old = Pool.new(settings, config(max_lifetime: 0.01))
        made = old.get
        sleep 0.05
        made.release

        assert_equal [0, 0], old.counts
      end

      # Verifies: [CLIENT Pools] of a server that takes neither Ping nor
      # Reset, the check ROLLBACK and the reset one pipeline: the
      # transaction rolled back, the statements prepared destroyed; a pool
      # made of anything that makes a connection.
      def test_a_pool_without_ping_or_reset
        source = -> { Client.connect_to(tcp, user: "ann", mechanism: Trust.new, offer: Offers.none) }
        pool = Pool.new(source, config(max: 1))
        pool.get do |c|
          c.prepare("VALUES 1")
          c.query("VALUES 1")

          assert_predicate c, :in_transaction?
        end
        pool.get do |c|
          assert_equal [false, 0], [c.in_transaction?, c.prepared_count]
          assert_equal [[1]], c.query("VALUES 1").rows
        end
      end

      # Verifies: [CLIENT Pools] the pool's clones shared by threads, each
      # wait the waiter's own; a connection that fails its check closed and
      # another made.
      def test_threads_share_a_pool
        pool = Pool.new(settings, config(max: 2, wait: 10))
        results = Array.new(6) { |i| Thread.new { pool.get { |c| c.query("VALUES #{i}").rows } } }.map(&:value)

        assert_equal (0...6).map { |i| [[i]] }, results
        idle = pool.instance_variable_get(:@idle)
        idle.first.first.abandon

        pool.get { |c| assert_equal [[7]], c.query("VALUES 7").rows }
      end

      # Verifies: [CLIENT The SQL-agent] a program's connections, each named,
      # one current: CONNECT through the program's connector, SET
      # CONNECTION, every other statement to the current connection,
      # DISCONNECT.
      def test_an_sql_agent
        port = server.port
        connector = ->(_server, user) { Client.connect("127.0.0.1", port, user: user || "ann", mechanism: Trust.new) }
        agent = Agent.new(connector)

        refused = assert_fails([-919, "08003"]) { agent.query("VALUES 1") }

        assert_equal "ISO/IEC 9075:1992 §15.3 GR9", refused.rule
        agent.query("CONNECT TO 'live' AS 'one' USER 'bob'")
        agent.query("CONNECT TO 'live' AS 'two'")

        assert_equal %w[TWO ANN], [agent.current_name, agent.current.authorization]
        agent.query("SET CONNECTION 'one'")

        assert_equal [["BOB"]], agent.query("VALUES CURRENT_USER").rows
        agent_failures(agent)
      end

      # What the agent refuses, and how it ends.
      def agent_failures(agent)
        assert_fails([-900, "0A001"]) { agent.query("SET CONNECTION 'two'") }
        agent.query("ROLLBACK")
        assert_fails([-919, "08002"]) { agent.query("CONNECT TO 'x' AS 'one'") }
        assert_fails([-919, "08003"]) { agent.query("DISCONNECT 'three'") }
        assert_equal "00000", agent.query("DISCONNECT 'two'").sqlstate
        assert_equal ["ONE", false, nil], [agent.current_name, agent.lost?, agent.warning]
        assert_kind_of Canceller, agent.canceller
        assert_equal "00000", agent.query("DISCONNECT ALL").sqlstate
        assert_nil agent.current_name
      end

      # Verifies: [CLIENT The SQL-agent] an agent begun with a default
      # connection, current; CONNECT TO DEFAULT and SET CONNECTION DEFAULT;
      # DISCONNECT CURRENT and DEFAULT; a user or a name that is no
      # identifier, a connector's failure, a transaction active refused.
      def test_agent_edges
        port = server.port
        connector = lambda do |address, user|
          raise Error.connection_failure("unreachable") if address == "nowhere"
          raise Error.of(-919, "28000", "refused") if address == "refusing"

          Client.connect("127.0.0.1", port, user: user || "ann", mechanism: Trust.new)
        end
        agent = Agent.new(connector, Client.connect("127.0.0.1", port, user: "ann", mechanism: Trust.new))

        assert_nil agent.current_name
        assert_fails([-919, "08002"]) { agent.query("CONNECT TO DEFAULT") }
        assert_fails([-104, "28000"]) { agent.query("CONNECT TO 'db' USER 'not one'") }
        assert_fails([-919, "2E000"]) { agent.query("CONNECT TO 'db' AS 'two words'") }
        assert_fails([-919, "08001"]) { agent.query("CONNECT TO 'nowhere'") }
        assert_fails([-919, "08004"]) { agent.query("CONNECT TO 'refusing'") }
        agent_moves(agent)
      end

      # The agent's connections chosen and ended.
      def agent_moves(agent)
        agent.query("CONNECT TO 'db' AS 'one'")
        agent.query("SET CONNECTION DEFAULT")
        agent.query("VALUES 1")
        assert_fails([-917, "25000"]) { agent.query("DISCONNECT CURRENT") }
        agent.query("ROLLBACK")
        agent.query("DISCONNECT CURRENT")

        assert_nil agent.current_connection
        assert_equal [nil, nil, false], [agent.canceller, agent.warning, agent.lost?]
        assert_fails([-919, "08003"]) { agent.query("DISCONNECT DEFAULT") }
        assert_fails([-919, "08003"]) { agent.query("DISCONNECT CURRENT") }
        assert_fails([-919, "08003"]) { agent.query("SET CONNECTION DEFAULT") }
        agent.query("SET CONNECTION 'one'")
        agent.query_into("VALUES 1", Object.new.tap do |sink|
          def sink.columns(_) = nil
          def sink.rows(_) = nil
        end)

        assert_equal "00000", agent.query_into("COMMIT", nil).sqlstate
        agent.current.abandon
        assert_fails { agent.terminate }
      end

      # Verifies: [CLIENT Pools] an idle connection that fails its check
      # closed and another made; a source that cannot make one failing
      # get, its place given back; more than 256 statements left prepared
      # on a server of no Reset closing the connection; a connection over a
      # stream the program opened, whose maker bounds it.
      def test_pool_edges
        pool = Pool.new(settings, config(max: 1))
        pool.get(&:ping)
        pool.instance_variable_get(:@idle).first.first.instance_variable_get(:@stream).close

        pool.get { |c| assert_equal [[1]], c.query("VALUES 1").rows }
        failing = Pool.new(-> { raise Error.of(-104, "28000", "the source's own") }, config(max: 1))
        own = assert_fails([-104, "28000"]) { failing.get }

        assert_equal "the source's own", own.message
        assert_equal [0, 0], failing.counts
        plain = -> { Client.connect_to(tcp, user: "ann", mechanism: Trust.new, offer: Offers.none) }
        many = Pool.new(plain, config(max: 1))
        many.get { |c| 257.times { c.prepare("VALUES 1") } }

        assert_equal [0, 0], many.counts
        opened = -> { Connection.open(TCPSocket.new("127.0.0.1", server.port), user: "ann", mechanism: Trust.new) }
        own = Pool.new(opened, config(max: 1))
        own.get(&:ping)

        assert_equal [1, 1], own.counts
      end
    end
  end
end
