# frozen_string_literal: true

require "test_helper"
require_relative "../../server/live_server"

module Turborel
  module Client
    # What a live server tells of a session, and how it is controlled
    # (RULES.md R-TEST-8), skipped without one.
    class LiveSessionTest < Minitest::Test
      include TestSupport
      include LiveServer::Case

      # A statement that completes with warning 01003, a null eliminated.
      WARNS = "SELECT SUM(V) FROM (VALUES (CAST(NULL AS INTEGER)), (1)) AS T(V)"
      # The names the server tells at login and after Reset or ChangeUser,
      # in its table's order.
      TABLE = %w[SERVER_VERSION AUTHORIZATION SCHEMA READ_ONLY SERVER_READ_ONLY CATALOG OWNER].freeze

      # Keeps each Status +connection+ receives from now on, in order.
      def statuses_of(connection)
        told = []
        connection.singleton_class.prepend(Module.new do
          define_method(:next_reply) do
            super().tap { |reply| told << reply.name if reply.is_a?(Protocol::Replies::Status) }
          end
        end)
        told
      end

      # Verifies: [CLIENT What the server tells] the rows a statement
      # changed or a query returned; the identity values an INSERT
      # generated; the server's time; the last commit's position.
      def test_what_the_server_tells_of_a_statement
        connect do |c|
          c.query("CREATE TABLE G (ID INTEGER GENERATED ALWAYS AS IDENTITY, V INTEGER)")
          c.query("INSERT INTO G (V) VALUES (5), (6), (7)")

          assert_equal [3, %w[1 2 3]], [c.rows_affected, c.last_generated]
          time = c.server_time

          assert_operator time.total, :>=, time.queued
          assert_operator time.total, :>=, time.locks
          assert_nil c.commit_position
          c.query("COMMIT")
          position = c.commit_position

          assert_operator position, :>, 0
          c.query("UPDATE G SET V = V + 1 WHERE V > 5")

          assert_equal [2, []], [c.rows_affected, c.last_generated]
          c.query("SELECT V FROM G")

          assert_equal [3, position], [c.rows_affected, c.commit_position]
          c.query("COMMIT")

          assert_operator c.commit_position, :>, position
        end
      end

      # Verifies: [PROTOCOL Errors and notices] a statement's conditions come
      # in its Complete with conditions, else as Notices with notices, else
      # not at all, of severity WARNING; a failing statement's as Notices.
      def test_conditions_told_one_way
        connect do |c|
          c.query(WARNS)

          assert_equal([%w[01003 WARNING]], c.conditions.map { [_1.sqlstate, _1.diagnostics.severity] })
          assert_equal ["01003", []], [c.warning, c.take_notices]
          assert_equal ["01003"], c.take_conditions.map(&:sqlstate)
          assert_empty c.take_conditions
          c.query("CREATE PROCEDURE WARN_THEN_FAIL() LANGUAGE SQL CONTAINS SQL BEGIN SIGNAL SQLSTATE '01ABC' " \
                  "SET MESSAGE_TEXT = 'first'; SIGNAL SQLSTATE '22ABC' SET MESSAGE_TEXT = 'then'; END")
          assert_fails([-401, "22ABC"]) { c.query("CALL WARN_THEN_FAIL()") }
          assert_equal ["01ABC"], c.take_notices.map(&:sqlstate)
          c.query("ROLLBACK")
        end
        told_otherwise
      end

      # A statement's condition as a Notice without conditions, and not at
      # all without notices too.
      def told_otherwise
        connect(offer: without(Protocol::Capabilities::CONDITIONS)) do |c|
          c.query(WARNS)

          assert_empty c.conditions
          assert_equal ["01003"], c.take_notices.map(&:sqlstate)
        end
        connect(offer: without(Protocol::Capabilities::CONDITIONS, Protocol::Capabilities::NOTICES)) do |c|
          c.query(WARNS)

          assert_equal [[], [], "01003"], [c.conditions, c.take_notices, c.warning]
        end
      end

      # Verifies: [CLIENT What the server tells] notices go to a handler as
      # they come, before the statement's last reply; with none, the last
      # are kept and taken.
      def test_notices_to_a_handler_or_kept
        connect(offer: without(Protocol::Capabilities::CONDITIONS)) do |c|
          order = []
          c.notice_handler = ->(notice) { order << "notice #{notice.sqlstate}" }
          sink = Object.new
          sink.define_singleton_method(:columns) { |_| order << "columns" }
          sink.define_singleton_method(:rows) { |_| order << "rows" }
          c.query_into(WARNS, sink)

          assert_equal ["columns", "rows", "notice 01003"], order
          c.notice_handler = nil
          c.query(WARNS)

          assert_equal 1, c.take_notices.size
        end
      end

      # Verifies: [PROTOCOL Capabilities] without diagnostics a failure has
      # none; without row-counts, generated-values or commit-position the
      # Complete says none of them; a method needing a capability not
      # granted fails before it sends anything; without fetch-ends a
      # cursor keeps its transaction.
      def test_capabilities_not_asked_for
        connect(offer: Offers.none) do |c|
          assert_nil assert_fails([-103, "2A000"]) { c.query("SELECT * FROM NOPE") }.failure.diagnostics
          c.query("CREATE TABLE H (ID INTEGER GENERATED ALWAYS AS IDENTITY, V INTEGER)")
          c.query("INSERT INTO H (V) VALUES (1)")

          assert_equal [nil, [], nil], [c.rows_affected, c.last_generated, c.server_time]
          c.query("COMMIT")

          assert_nil c.commit_position
          c.query(WARNS)

          assert_equal [[], []], [c.conditions, c.take_notices]
          refused_methods(c)
        end
      end

      # Each method needing a capability Offers.none did not ask for fails,
      # the connection kept.
      def refused_methods(connection)
        [-> { connection.ping }, -> { connection.reset }, -> { connection.query_many("VALUES 1") },
         -> { connection.change_user("bob", Trust.new) },
         -> { connection.query_attributes = [%w[app x]] }].each { |refused| assert_fails(&refused) }
        statement = connection.prepare("VALUES (1), (2), (3)")
        assert_fails { connection.describe(statement) }
        assert_fails { connection.open_cursor_numbered(statement, 1) }
        refute_predicate connection, :lost?
        connection.autocommit = true
        connection.open_cursor(statement, [], 1)
        connection.fetch(statement)

        assert_predicate connection, :in_transaction?
        connection.query("COMMIT")
      end

      # Verifies: [PROTOCOL Reset 'W'] ping; reset rolls the transaction
      # back, told by notice 01T01, its statements, temporary
      # tables and settings gone, every setting told again, its user and
      # cancel key kept.
      def test_ping_and_reset
        connect do |c|
          c.ping
          c.query("SET TIME ZONE INTERVAL '+02:00' HOUR TO MINUTE")

          assert_equal "+02:00", c.setting("SESSION.TIME_ZONE")
          c.query("DECLARE LOCAL TEMPORARY TABLE MODULE.TMP (X INTEGER)")
          statement = c.prepare("VALUES 1")
          c.query("VALUES 1")
          key = c.instance_variable_get(:@key)
          told = statuses_of(c)
          c.reset

          assert_equal [false, key, "ANN"], [c.in_transaction?, c.instance_variable_get(:@key), c.authorization]
          assert_equal([%w[01T01 NOTICE]], c.take_notices.map { [_1.sqlstate, _1.diagnostics.severity] })
          assert_equal TABLE, told.first(TABLE.size)
          assert_equal "+00:00", c.setting("SESSION.TIME_ZONE")
          after_reset(c, statement)
        end
      end

      # A second reset, with no transaction, tells no notice; the statements
      # and temporary tables are gone.
      def after_reset(connection, statement)
        connection.reset

        assert_empty connection.take_notices
        assert_fails([-921, "26000"]) { connection.execute(statement) }
        assert_fails([-103, "2A000"]) { connection.query("SELECT X FROM MODULE.TMP") }
      end

      # Verifies: [PROTOCOL Status 'T'] at login, before Ready, one of each
      # name in the page's table in its order, then the session's own
      # settings; after a statement only what it changed, before its
      # completion; nothing after one that changed nothing.
      def test_statuses_in_order
        connect do |c|
          assert_equal TABLE, c.settings.keys.first(TABLE.size)
          assert_operator c.settings.size, :>, TABLE.size
          told = statuses_of(c)
          c.query("VALUES 1")

          assert_empty told
          c.query("SET TIME ZONE INTERVAL '+05:00' HOUR TO MINUTE")

          assert_equal ["SESSION.TIME_ZONE"], told
          assert_equal "+05:00", c.setting("SESSION.TIME_ZONE")
        end
      end

      # Verifies: [CLIENT Controlling the session] change of user: the
      # session renewed as the new user's under a new cancel key, a
      # transaction rolled back by notice 01T01 and none active after; a
      # refusal closes the connection.
      def test_change_user
        connect(Targets.local(server.socket)) do |c|
          key = c.instance_variable_get(:@key)
          c.query("VALUES 1")
          c.change_user("bob", Password.new(LiveServer::USERS["bob"]))

          assert_equal %w[BOB BOB], [c.authorization, c.setting("AUTHORIZATION")]
          refute_equal key, c.instance_variable_get(:@key)
          assert_equal Offers.default.capabilities, c.granted
          assert_equal ["01T01"], c.take_notices.map(&:sqlstate)
          refute_predicate c, :in_transaction?
          changed_back_and_refused(c)
        end
      end

      # A change back to ANN, then one refused, which closes the connection.
      def changed_back_and_refused(connection)
        connection.change_user("ann", Trust.new)

        assert_equal "ANN", connection.authorization
        refused = assert_fails([-919, "28000"]) { connection.change_user("bob", Password.new("wrong")) }

        assert_equal "FATAL", refused.failure.diagnostics.severity
        assert_predicate connection, :lost?
      end

      # Verifies: [CLIENT Controlling the session] query attributes are
      # carried by every later statement, until set again.
      def test_query_attributes
        connect do |c|
          read = "VALUES QUERY_ATTRIBUTE('app')"
          c.query_attributes = [%w[app reports]]

          assert_equal [["reports"]], c.query(read).rows
          assert_equal [["reports"]], c.execute(c.prepare(read)).rows
          c.query_attributes = []

          assert_equal [[nil]], c.query(read).rows
        end
      end

      # Verifies: [PROTOCOL Hello 'H'] connection attributes in Hello, which
      # the server reads whether connection-attributes is granted or not;
      # no tail field of a capability not granted, as tag 6, sent back.
      def test_connection_attributes
        [Offers.default, Offers.none].each do |offer|
          connect(offer: Offers.attribute(offer, "application", "turborel-ruby live")) do |c|
            rows = c.query("SELECT ATTRIBUTE_VALUE FROM INFORMATION_SCHEMA.CONNECTION_ATTRIBUTES " \
                           "WHERE ATTRIBUTE_NAME = 'application'").rows

            assert_equal [["turborel-ruby live"]], rows
          end
        end
        connect(offer: Offers.none) do |c|
          c.query("VALUES 1")

          assert_nil c.completion.rows
        end
      end

      # Verifies: [CLIENT XML values] an XML value read as its serialization
      # and parsed for its nodes; a parameter made of its text; one with no
      # serialization fails the fetch (2200W).
      def test_xml_values
        connect do |c|
          c.query("CREATE TABLE ORDERS (ID INTEGER, BODY XML)")
          c.execute(c.prepare("INSERT INTO ORDERS VALUES (?, ?)"),
                    [18, Xml.new(text: '<order no="18"><item>jam</item></order>')])
          body = c.query("SELECT BODY FROM ORDERS WHERE ID = 18").rows.first.first

          assert_equal '<order no="18"><item>jam</item></order>', body.text
          assert_equal "18", body.nodes.first.attributes.first.value
          assert_fails([-301, "2200W"]) do
            c.query("SELECT XMLQUERY('$b/order/@no' PASSING BY VALUE BODY AS \"b\" RETURNING SEQUENCE NULL ON EMPTY) " \
                    "FROM ORDERS")
          end
          c.query("ROLLBACK")
        end
      end

      # Verifies: [CLIENT UUIDs] a UUID read as its octets and text; a
      # parameter made of its octets or its text.
      def test_uuids
        connect do |c|
          c.query("CREATE TABLE TICKETS (ID UUID, SEAT VARCHAR(4))")
          insert = c.prepare("INSERT INTO TICKETS VALUES (?, ?)")
          text = "919108f7-52d1-4320-9bac-f847db4148a8"
          c.execute(insert, [Uuid.parse(text), "12A"])
          c.execute(insert, [Uuid.new(octets: ("\xAB" * 16).b), "12B"])
          first, second = c.query("SELECT ID FROM TICKETS ORDER BY SEAT").rows.map(&:first)

          assert_equal text, first.text
          assert_equal ("\xAB" * 16).b, second.octets
          c.query("ROLLBACK")
        end
      end

      # Verifies: [PROTOCOL Execute 'E'] a CALL with a ? for an OUT or INOUT
      # parameter: its parameters the inputs alone, its columns one for
      # each output ?, in the procedure's order; its Execute sends their
      # values as one row before its Complete.
      def test_call_output_parameters
        connect do |c|
          c.query("CREATE PROCEDURE SPLIT(IN A INTEGER, OUT HALF INTEGER, INOUT TOTAL INTEGER) LANGUAGE SQL " \
                  "CONTAINS SQL BEGIN SET HALF = A / 2; SET TOTAL = TOTAL + A; END")
          call = c.prepare("CALL SPLIT(?, ?, ?)")

          assert_equal 2, call.parameters.size
          assert_equal %w[HALF TOTAL], call.columns.map(&:name)
          assert_equal [[5, 13]], c.execute(call, [10, 3]).rows
          c.query("ROLLBACK")
        end
      end

      # Verifies: [PROTOCOL Cancel 'Z'] a statement cancelled over a
      # connection of its own fails with SQLCODE -920, SQLSTATE TB920, and
      # the session goes on.
      def test_cancel_a_statement
        connect do |c|
          c.query("CREATE TABLE CANCELLED (I INTEGER)")
          c.query("INSERT INTO CANCELLED VALUES #{(0...300).map { "(#{_1})" }.join(", ")}")
          canceller = c.canceller
          running = Thread.new do
            c.query("SELECT COUNT(*) FROM CANCELLED A, CANCELLED B, CANCELLED C")
          rescue Error => e
            e
          end
          canceller.cancel while running.alive?

          assert_equal([-920, "TB920"], running.value.then { [_1.sqlcode, _1.sqlstate] })
          assert_equal [[300]], c.query("SELECT COUNT(*) FROM CANCELLED").rows
        end
      end
    end
  end
end
