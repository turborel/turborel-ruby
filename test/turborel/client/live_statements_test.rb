# frozen_string_literal: true

require "test_helper"
require_relative "../../server/live_server"

module Turborel
  module Client
    # Statements run on a live server (RULES.md R-TEST-8), skipped without
    # one.
    class LiveStatementsTest < Minitest::Test
      include TestSupport
      include LiveServer::Case

      # A sink that keeps what it is given.
      class Kept
        attr_reader :columns_given, :batches

        def initialize
          @batches = []
          @columns_given = nil
        end

        def columns(columns) = @columns_given = columns

        def rows(rows) = @batches << rows.size
      end

      # Gives the block a connection with the table +name+ of +count+ rows,
      # (1, 'N1') and on, committed.
      def with_table(name, count, &)
        connect do |c|
          c.query("CREATE TABLE #{name} (ID INTEGER PRIMARY KEY, NAME VARCHAR(20))")
          values = (1..count).map { |i| "(#{i}, 'N#{i}')" }.join(", ")
          c.query("INSERT INTO #{name} VALUES #{values}")
          c.query("COMMIT")
          yield c
        end
      end

      # Verifies: [CLIENT Running statements] a query's columns and rows;
      # another statement's completion, 02000 for no row; a failure's
      # SQLCODE, SQLSTATE, message, rule, position and diagnostics.
      def test_queries_statements_and_failures
        with_table("STAFF", 2) do |c|
          staff = c.query("SELECT ID, NAME FROM STAFF ORDER BY ID")

          assert_equal %w[ID NAME], staff.columns.map(&:name)
          assert_equal [[1, "N1"], [2, "N2"]], staff.rows
          none = c.query("DELETE FROM STAFF WHERE ID = 9")

          assert_equal [100, "02000"], [none.sqlcode, none.sqlstate]
          failing_statements(c)
        end
      end

      # A failure's SQLCODE, SQLSTATE, message, rule, position and
      # diagnostics.
      def failing_statements(connection)
        missing = assert_fails([-103, "2A000"]) { connection.query("SELECT * FROM NOPE") }

        assert_equal "table ANN.NOPE is not defined", missing.message
        assert_equal(%w[ERROR ANN NOPE], missing.failure.diagnostics.then { [_1.severity, _1.schema, _1.table] })
        refute_nil missing.failure.rule
        duplicate = assert_fails([-201, "23000"]) { connection.query("INSERT INTO STAFF VALUES (1, 'Dup')") }

        assert_equal "STAFF_PRIMARY1", duplicate.failure.diagnostics.constraint
        assert_equal "the key (1) is held by another row", duplicate.failure.diagnostics.detail
        refute_nil assert_fails([-102, "2A000"]) { connection.query("SELECT FROM") }.failure.position
      end

      # Verifies: [CLIENT Running statements] a query's rows given to a sink
      # a batch at a time, as they come; another statement's completion as
      # it is.
      def test_rows_a_batch_at_a_time
        with_table("MANY", 100) do |c|
          sink = Kept.new

          assert_equal 10_000, c.query_into("SELECT A.ID, B.ID FROM MANY A, MANY B", sink)
          assert_equal 2, sink.columns_given.size
          assert_operator sink.batches.size, :>, 1
          assert_equal 10_000, sink.batches.sum
          assert_equal "00000", c.query_into("COMMIT", sink).sqlstate
        end
      end

      # Verifies: [CLIENT Running statements] every kind of value: exact,
      # approximate, character, binary, datetime, interval, a plug-in's,
      # null.
      def test_every_kind_of_value
        connect do |c|
          row = c.query("VALUES (CAST(1.5 AS DECIMAL(5,2)), CAST(1.5 AS DOUBLE PRECISION), 'x', X'0A', " \
                        "DATE '2026-11-19', INTERVAL '1' DAY, ST_POINT(1, 2), CAST(NULL AS INTEGER), TRUE, 7)")
                 .rows.first
          exact, approximate, char, binary, date, interval, plugin, nothing, truth, integer = row

          assert_equal [BigDecimal("1.5"), 1.5, "x", "\n".b], [exact, approximate, char, binary]
          assert_equal Encoding::BINARY, binary.encoding
          assert_equal [:date, 63_930_643_200_000_000], [date.moment, date.utc]
          assert_equal 86_400_000_000, interval.units
          assert_equal ["ST_GEOMETRY", "POINT (1 2)"], [plugin.name, plugin.text]
          assert_equal [nil, true, 7], [nothing, truth, integer]
        end
      end

      # Verifies: [CLIENT Running statements] a transaction begun by the
      # first statement lasts until COMMIT or ROLLBACK, as the connection
      # tells; under autocommit each statement is its own, committed as it
      # succeeds, rolled back as it fails, a failing commit's Error in
      # place of its Complete.
      def test_transactions_and_autocommit
        with_table("TX", 1) do |c|
          refute_predicate c, :in_transaction?
          c.query("INSERT INTO TX VALUES (2, 'two')")

          assert_predicate c, :in_transaction?
          c.query("ROLLBACK")

          refute_predicate c, :in_transaction?
          c.autocommit = true
          c.query("INSERT INTO TX VALUES (3, 'three')")

          refute_predicate c, :in_transaction?
          autocommitted(c)
        end
      end

      # Under autocommit a failing statement and a failing commit roll back.
      def autocommitted(connection)
        assert_fails([-201, "23000"]) { connection.query("INSERT INTO TX VALUES (3, 'again')") }
        refute_predicate connection, :in_transaction?
        connect { |other| assert_equal [[1], [3]], other.query("SELECT ID FROM TX ORDER BY ID").rows }
        connection.query("CREATE TABLE DEF (ID INTEGER, CONSTRAINT POS CHECK (ID > 0) INITIALLY DEFERRED)")
        assert_fails([-913, "40002"]) { connection.query("INSERT INTO DEF VALUES (-1)") }
        refute_predicate connection, :in_transaction?
      end

      # Verifies: [PROTOCOL Query 'Q'] a result that sent a locator keeps
      # its transaction, under autocommit too.
      def test_a_locator_keeps_its_transaction
        connect do |c|
          c.query("CREATE TABLE DOCS (ID INTEGER, C CLOB(1M))")
          c.execute(c.prepare("INSERT INTO DOCS VALUES (1, ?)"), ["x" * 70_000])
          c.query("COMMIT")
          c.autocommit = true
          doc = c.query("SELECT C FROM DOCS").rows.first.first

          assert_kind_of Lob, doc
          refute_nil doc.locator
          assert_predicate c, :in_transaction?
          c.query("COMMIT")
        end
      end

      # Verifies: [CLIENT Controlling the session] several statements as one
      # request: each outcome in turn, and the failure that stopped the
      # rest; text of no statement, one completion.
      def test_several_statements_in_one_request
        with_table("MULTI", 1) do |c|
          ran = c.query_many("INSERT INTO MULTI VALUES (2, 'b'); SELECT ID FROM MULTI ORDER BY ID; COMMIT")

          assert_equal [Completion, Rows, Completion], ran.outcomes.map(&:class)
          assert_equal [[1], [2]], ran.outcomes[1].rows
          assert_nil ran.failure
          stopped = c.query_many("INSERT INTO MULTI VALUES (3, 'c'); INSERT INTO MULTI VALUES (3, 'd'); COMMIT")

          assert_equal 1, stopped.outcomes.size
          assert_equal "23000", stopped.failure.sqlstate
          assert_equal 1, c.query_many("").outcomes.size
          c.query("ROLLBACK")
        end
      end

      # Verifies: [CLIENT Prepared statements] prepared once, its parameters'
      # types and columns given; executed with values as often as wanted,
      # across transactions; described again; deallocated.
      # Verifies: [CLIENT Controlling the session] a prepared statement
      # described again.
      def test_prepared_statements
        with_table("PREP", 3) do |c|
          by_id = c.prepare("SELECT NAME FROM PREP WHERE ID = ?")

          assert_equal :exact, by_id.parameters.first.type.kind
          assert_equal ["NAME"], by_id.columns.map(&:name)
          assert_equal [["N2"]], c.execute(by_id, [2]).rows
          c.query("COMMIT")

          assert_equal [["N3"]], c.execute(by_id, [3]).rows
          insert = c.prepare("INSERT INTO PREP VALUES (?, ?)")

          assert_equal 0, c.execute(insert, [4, "N4"]).sqlcode
          described_and_deallocated(c, by_id, insert)
        end
      end

      # +by_id+ described again, +insert+ refused short a value and
      # deallocated, then gone.
      def described_and_deallocated(connection, by_id, insert)
        assert_fails([-921, "07001"]) { connection.execute(insert, [5]) }
        assert_equal by_id.columns, connection.describe(by_id).columns
        connection.deallocate(insert)
        assert_fails([-921, "26000"]) { connection.execute(insert, [6, "N6"]) }
        assert_fails([-921, "26000"]) { connection.deallocate(insert) }
        assert_fails([-102, "37000"]) { connection.prepare("SELECT FROM") }
        connection.query("ROLLBACK")
      end

      # Verifies: [CLIENT Prepared statements] a cursor opened with its first
      # rows, fetched a batch at a time, closed; several numbered cursors at
      # once; described while open; a statement whose cursor is open not
      # replaced, nor opened again, nor deallocated (24000).
      # Verifies: [CLIENT Controlling the session] several numbered cursors
      # of one statement open at once; an open cursor's columns described.
      # Verifies: [PROTOCOL Prepare 'P'] a statement whose cursor is open not
      # replaced (24000).
      # Verifies: [PROTOCOL Execute 'E'] a cursor already open not opened
      # again (24000).
      # Verifies: [PROTOCOL Fetch 'F'] a cursor not open not fetched
      # (24000).
      # Verifies: [PROTOCOL Deallocate 'D'] a statement whose cursor is open
      # not deallocated (24000).
      def test_cursors
        with_table("CUR", 5) do |c|
          all = c.prepare("SELECT ID FROM CUR ORDER BY ID")

          assert_equal Batch.new(rows: [[1], [2]], more: true), c.open_cursor(all, [], 2)
          assert_fails([-501, "24000"]) { c.open_cursor(all) }
          assert_fails([-501, "24000"]) { c.deallocate(all) }
          assert_equal Batch.new(rows: [[3], [4]], more: true), c.fetch(all, 2)
          assert_equal Batch.new(rows: [[5]], more: false), c.fetch(all)
          assert_fails([-501, "24000"]) { c.fetch(all) }
          numbered(c, all)
          c.query("COMMIT")
        end
      end

      # Two numbered cursors of +all+ open at once, then the statement
      # replaced once they are closed.
      def numbered(connection, all)
        connection.open_cursor_numbered(all, 1, [], 1)
        connection.open_cursor_numbered(all, 2, [], 3)

        assert_equal ["ID"], connection.describe_cursor(all, 2).map(&:name)
        assert_equal [[2]], connection.fetch(all, 1, cursor: 1).rows
        assert_equal [[4]], connection.fetch(all, 1, cursor: 2).rows
        assert_fails([-501, "24000"]) { prepare_again(connection, all, "VALUES 1") }
        connection.close(all, cursor: 1)
        connection.close(all, cursor: 2)
        replaced = prepare_again(connection, all, "VALUES ('replaced')")

        assert_equal [["replaced"]], connection.execute(replaced).rows
        assert_fails([-501, "24000"]) { connection.close(all, cursor: 2) }
      end

      # Prepares +sql+ under the number of +statement+.
      def prepare_again(connection, statement, sql)
        connection.__send__(:send_frame, Protocol::Requests.prepare(statement.number, sql))
        connection.__send__(:prepared)
      end

      # Verifies: [PROTOCOL Conversations] a cursor read in parts under
      # autocommit with fetch-ends, its transaction ending as it does: its last row's fetch commits,
      # close commits, a failing fetch rolls back (2200W, a value the server
      # cannot serialize).
      # Verifies: [CLIENT What the server tells] under autocommit with
      # fetch-ends, a cursor's transaction ended as it ends.
      def test_a_cursor_ends_its_transaction
        with_table("ENDS", 3) do |c|
          c.autocommit = true
          all = c.prepare("SELECT ID FROM ENDS ORDER BY ID")
          c.open_cursor(all, [], 1)

          assert_predicate c, :in_transaction?
          c.fetch(all)

          refute_predicate c, :in_transaction?
          c.open_cursor(all, [], 1)
          c.close(all)

          refute_predicate c, :in_transaction?
          failing_fetch(c)
        end
      end

      # A cursor whose fourth row's value, an attribute alone, has no
      # serialization: the fetch that sends it fails.
      def failing_fetch(connection)
        connection.query("CREATE TABLE MARKED (ID INTEGER, B XML)")
        (1..4).each do |id|
          connection.query("INSERT INTO MARKED VALUES (#{id}, " \
                           "XMLPARSE(CONTENT '<a n=\"#{id}\">#{id}</a>' PRESERVE WHITESPACE))")
        end
        failing = connection.prepare("SELECT XMLQUERY('$b/a[. = 4]/@n' PASSING BY VALUE B AS \"b\" " \
                                     "RETURNING SEQUENCE NULL ON EMPTY) FROM MARKED ORDER BY ID")
        connection.open_cursor(failing, [], 1)

        assert_predicate connection, :in_transaction?
        assert_fails([-301, "2200W"]) { connection.fetch(failing) }
        refute_predicate connection, :in_transaction?
      end

      # Verifies: [PROTOCOL Declared types] granted declared-types, a
      # Description and a Prepared tell each column's declared type, its
      # name and as SQL writes it, the values written by their own tags: a
      # VALUES of casts, and a UNION of one number type, keeping it, one of
      # INTEGER and SMALLINT NUMERIC; not granted, the columns alone, typed
      # by their tags.
      # Verifies: [PROTOCOL Capabilities] declared-types, granted where
      # asked, as every connection asks it by default.
      # Verifies: [PROTOCOL The tail] tag 19, declared, on a Prepared and a
      # Description.
      # Verifies: [CLIENT Prepared statements] a column's declared type, its
      # type written as declared where told, else as its tag says.
      def test_declared_types
        connect do |c|
          c.query("CREATE TABLE DECL (I INTEGER, M NUMERIC(5), F FLOAT(20))")
          c.query("INSERT INTO DECL VALUES (1, 2, 3)")
          rows = c.query("SELECT I, M, F FROM DECL")
          prepared = c.prepare("SELECT I FROM DECL")

          assert c.granted?(Protocol::Capabilities::DECLARED_TYPES)
          assert_equal([%w[INTEGER INTEGER], ["NUMERIC", "NUMERIC(5,0)"], ["FLOAT", "FLOAT(24)"]],
                       rows.columns.map { [_1.declared.name, _1.type_written] })
          assert_equal [[1, 2, 3.0], "INTEGER"], [rows.rows.first, prepared.columns.first.type_name]
          declared = ->(sql) { c.query(sql).columns.map(&:type_written) }

          assert_equal [%w[INTEGER SMALLINT], ["INTEGER"], ["NUMERIC(10,0)"]],
                       [declared.call("VALUES (CAST(1 AS INTEGER), CAST(2 AS SMALLINT))"),
                        declared.call("SELECT I FROM DECL UNION SELECT I FROM DECL"),
                        declared.call("SELECT I FROM DECL UNION SELECT CAST(1 AS SMALLINT) FROM DECL")]
          c.query("COMMIT")
        end
        connect(offer: without(Protocol::Capabilities::DECLARED_TYPES)) do |c|
          columns = c.query("SELECT I, M FROM DECL").columns

          assert_equal([[nil, "NUMERIC(10,0)"], [nil, "NUMERIC(5,0)"]], columns.map { [_1.declared, _1.type_written] })
          c.query("DROP TABLE DECL CASCADE")
          c.query("COMMIT")
        end
      end
    end
  end
end
