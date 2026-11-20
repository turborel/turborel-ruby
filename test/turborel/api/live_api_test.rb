# frozen_string_literal: true

require "test_helper"
require_relative "../../server/live_server"

module Turborel
  # The plain API on a live server (RULES.md R-TEST-8), skipped without
  # one.
  class LiveApiTest < Minitest::Test
    include TestSupport
    include LiveServer::Case

    def uri = "turborel://ann@127.0.0.1:#{server.port}/?tls_mode=disable"

    def plain
      connection = Turborel.connect(uri) { nil }
      yield connection
    ensure
      connection&.close
    end

    # Verifies: [DESIGN] D2 Turborel.connect by a turborel:// URI, by
    # settings by name over it, or by Client::Settings, each giving a
    # Turborel::Connection; autocommit off, as Turborel's; close ending it.
    def test_connect
      by_uri = Turborel.connect(uri) { nil }
      by_options = Turborel.connect(host: "127.0.0.1", port: server.port, user: "bob", tls_mode: "disable") { nil }
      over = Turborel.connect(uri, application_name: "plain") { nil }
      by_settings = Turborel.connect(Client::Settings.from_uri(uri) { nil })

      assert_equal(%w[ANN BOB ANN ANN], [by_uri, by_options, over, by_settings].map { _1.client.authorization })
      assert_equal [false, false], [by_uri.autocommit, by_uri.in_transaction?]
      assert_match(/\A#<Turborel::Connection #<Turborel::Client::Connection/, by_uri.inspect)
      [by_uri, by_options, over, by_settings].each(&:finish)

      assert_predicate by_uri, :finished?
      by_uri.close
      assert_fails([-919, "08001"]) { Turborel.connect(uri, nonsense: "1") { nil } }
    end

    # Verifies: [DESIGN] D2 exec of a statement's text; exec_params with ?
    # parameters, prepared, executed and destroyed; each value as Appendix A
    # maps it; the rows a statement counted.
    def test_exec_and_exec_params
      plain do |c|
        c.autocommit = true
        c.exec("CREATE TABLE PLAIN (ID INTEGER PRIMARY KEY, NAME VARCHAR(10), BORN DATE)")
        inserted = c.exec_params("INSERT INTO PLAIN VALUES (?, ?, ?)", [1, "Ada", nil])
        c.exec("INSERT INTO PLAIN VALUES (2, 'Grace', DATE '1906-12-09')")
        rows = c.exec_params("SELECT ID, NAME, BORN FROM PLAIN WHERE ID >= ? ORDER BY ID", [1])

        assert_equal [1, "00000", %w[ID NAME BORN]], [inserted.cmd_tuples, inserted.sqlstate, rows.fields]
        assert_equal [[1, "Ada", nil], [2, "Grace"]], [rows.values.first, rows.values.last.first(2)]
        assert_kind_of Datetime, rows.getvalue(1, 2)
        assert_equal [0, "02000"], [c.exec("DELETE FROM PLAIN WHERE ID = 9").cmd_tuples,
                                    c.exec("DELETE FROM PLAIN WHERE ID = 9").sqlstate]
        assert_equal 0, c.client.prepared_count - 2
      end
    end

    # Verifies: [DESIGN] D2 prepare under a name, its columns given, and
    # exec_prepared with values; a name prepared again replaced; deallocate;
    # a name no statement is prepared under refused as EXECUTE refuses it.
    def test_prepare_and_exec_prepared
      plain do |c|
        prepared = c.prepare("double", "VALUES CAST(? AS INTEGER) * 2")

        assert_equal [[nil], 0], [prepared.fields, prepared.ntuples]
        assert_equal [[6]], c.exec_prepared("double", [3]).values
        c.prepare("double", "VALUES CAST(? AS INTEGER) * 3")

        assert_equal [[9]], c.exec_prepared("double", [3]).values
        c.deallocate("double")
        assert_fails([-921, "26000"]) { c.exec_prepared("double", [3]) }
        assert_fails([-921, "26000"]) { c.deallocate("double") }
      end
    end

    # Verifies: [DESIGN] D2 transaction: the block's statements committed as
    # it ends, its value given; rolled back as it raises, the exception
    # raised again; autocommit put back after; one begun while a transaction
    # is active refused.
    def test_transactions
      plain do |c|
        c.autocommit = true
        c.exec("CREATE TABLE TXN (ID INTEGER PRIMARY KEY)")
        value = c.transaction { |t| t.exec("INSERT INTO TXN VALUES (1)") && :kept }

        assert_raises(ArgumentError) do
          c.transaction do |t|
            t.exec("INSERT INTO TXN VALUES (2)") && raise(ArgumentError)
          end
        end
        assert_equal [:kept, true, [[1]]], [value, c.autocommit, c.exec("SELECT ID FROM TXN").values]
        c.autocommit = false
        c.exec("VALUES 1")
        assert_fails(MISUSED) { c.transaction { flunk } }
        c.exec("ROLLBACK")
      end
    end

    # Verifies: [DESIGN] D2 every failure of the plain API a Turborel::Error
    # carrying the server's failure; parameters' values not an Array
    # refused.
    def test_failures
      plain do |c|
        error = assert_raises(Error) { c.exec("SELECT * FROM NOWHERE") }

        assert_equal [-103, "2A000", "NOWHERE"], [error.sqlcode, error.sqlstate, error.diagnostics.table]
        assert_fails([-301, "22012"]) { c.exec_params("VALUES 1 / CAST(? AS INTEGER)", [0]) }
        assert_fails(MISUSED) { c.exec_params("VALUES 1", "1") }
        c.prepare("one", "VALUES 1")
        assert_fails(MISUSED) { c.exec_prepared("one", nil) }
        c.client.define_singleton_method(:execute) do |*|
          abandon
          raise Error.connection_failure("lost while executing")
        end
        assert_fails { c.exec_params("VALUES 1", []) }
        assert_fails { c.exec_params("VALUES 1", []) }
      end
    end

    # Verifies: [DESIGN] D2 a value bound to a ? mark longer than the mark's
    # type cut to it, as a cast does, with warning 01004, string data, right
    # truncation.
    def test_a_value_cut_warns
      plain do |c|
        c.exec("CREATE TABLE CUT (S VARCHAR(5))")
        cut = c.exec_params("INSERT INTO CUT VALUES (?)", ["abcdefgh"])

        assert_equal ["01004", [["abcde"]]], [cut.sqlstate, c.exec("SELECT S FROM CUT").values]
        c.exec("ROLLBACK")
      end
    end

    # Verifies: [DESIGN] D2 a result's column types by the type each was
    # declared with: its name as DATA_TYPE gives it, and as SQL writes it.
    def test_declared_types
      plain do |c|
        c.exec("CREATE TABLE TYPED (I INTEGER, N NUMERIC(5), D DECIMAL(9,2), F FLOAT(20), S VARCHAR(10))")
        result = c.exec("SELECT I, N, D, F, S FROM TYPED")

        assert_equal ["INTEGER", "NUMERIC", "DECIMAL", "FLOAT", "CHARACTER VARYING"], result.ftypes
        assert_equal(["INTEGER", "NUMERIC(5,0)", "DECIMAL(9,2)", "FLOAT(24)", "CHARACTER VARYING(10)"],
                     (0...5).map { result.type_written(_1) })
        assert_equal "INTEGER", c.prepare("typed", "SELECT I FROM TYPED").ftype(0)
        assert_fails(MISUSED) { result.ftype(5) }
        c.exec("ROLLBACK")
      end
    end
  end
end
