# frozen_string_literal: true

require "stringio"
require "test_helper"
require_relative "../../server/live_server"

module Turborel
  module Client
    # Large objects, copies and exports on a live server (RULES.md
    # R-TEST-8), skipped without one.
    class LiveBulkTest < Minitest::Test
      include TestSupport
      include LiveServer::Case

      # Verifies: [PROTOCOL Values] a large object of at most 64 KiB read
      # whole in its row; a longer one by its locator and lengths, which a
      # reader reads whole a chunk at a time; one sent as a locator the
      # client made, written a piece at a time.
      # Verifies: [CLIENT Large objects] a short value whole in its row, a
      # longer one by its locator; a value made a piece at a time through a
      # writer, passed as a parameter.
      def test_large_objects
        connect do |c|
          c.query("CREATE TABLE SCANS (ID INTEGER, IMAGE BLOB(10M), NOTE CLOB(1M))")
          writer = c.create_lob(:binary)
          1024.times { writer.write(("\x07" * 4096).b) }
          note = c.create_lob(:character).tap { |w| w << ("é" * 40_000) << "x" }.finish
          c.execute(c.prepare("INSERT INTO SCANS VALUES (1, ?, ?), (2, ?, ?)"),
                    [writer.finish, note, "\x01\x02".b, "short"])
          c.query("COMMIT")
          rows = c.query("SELECT IMAGE, NOTE FROM SCANS ORDER BY ID").rows
          image, text = rows.first

          assert_equal [4_194_304, 40_001, nil, nil], [image.octets, text.characters, image.data, text.data]
          assert_equal [("\x07" * 4_194_304).b, "\x01\x02".b, "short"],
                       [c.lob_reader(image).read, *rows.last.map(&:data)]
          assert_equal "ééx", c.read_lob(text, 39_998, 3, characters: true).force_encoding(Encoding::UTF_8)
          c.query("COMMIT")
        end
      end

      # Verifies: [CLIENT Large objects] a locator valid until its
      # transaction ends, the transaction kept under autocommit too; held
      # past the commit until freed; freed, no longer valid (0F001).
      # Verifies: [PROTOCOL Lob 'L'] hold: a locator kept past its
      # transaction's commit, answered by Complete.
      def test_locators_hold_and_free
        connect do |c|
          c.query("CREATE TABLE HELD (B BLOB(1M))")
          c.query("INSERT INTO HELD VALUES (CAST(X'#{"AB" * 70_000}' AS BLOB(1M)))")
          c.query("COMMIT")
          c.autocommit = true
          lob = c.query("SELECT B FROM HELD").rows.first.first

          assert_predicate c, :in_transaction?
          assert_equal "00000", c.hold_lob(lob).sqlstate
          c.query("COMMIT")

          assert_equal "\xAB\xAB".b, c.read_lob(lob, 0, 2)
          c.free_lob(lob)
          assert_fails([-301, "0F001"]) { c.read_lob(lob, 0, 2) }
          c.query("ROLLBACK")
        end
      end

      # Verifies: [PROTOCOL Conversations] a copy: CopyIn, CopyData, Ping
      # answered within it, CopyEnd answered by a Complete counting the rows;
      # under autocommit the copy commits as it ends.
      def test_a_copy
        connect do |c|
          c.query("CREATE TABLE COPIED (ID INTEGER PRIMARY KEY, NAME VARCHAR(20))")
          c.query("COMMIT")
          c.autocommit = true
          copy = c.copy_in("COPIED", %w[ID NAME])
          copy << [7, "Niklaus"] << [8, "Barbara"]
          c.ping

          assert_equal 2, copy.finish
          refute_predicate c, :in_transaction?
          connect { |other| assert_equal [[7], [8]], other.query("SELECT ID FROM COPIED ORDER BY ID").rows }
          assert_equal 0, c.copy_in("COPIED") { |abandoned| abandoned << [9, "x"] and abandoned.abandon }
          assert_equal [[2]], c.query("SELECT COUNT(*) FROM COPIED").rows
        end
      end

      # Verifies: [PROTOCOL Conversations] a copy whose row breaks a
      # constraint: every row of it undone, the failure's detail naming the
      # row; a copy within a transaction undone alone, as under a savepoint
      # of its own; the copy's columns, all of the table's if none named.
      def test_a_copy_whose_row_breaks_a_constraint
        connect do |c|
          c.query("CREATE TABLE BROKEN (ID INTEGER PRIMARY KEY, NAME VARCHAR(20))")
          c.query("COMMIT")
          c.query("INSERT INTO BROKEN VALUES (10, 'kept')")
          refused = assert_fails([-201, "23000"]) { c.copy_rows("BROKEN", [], [[1, "a"], [2, "b"], [1, "c"]]) }

          assert_equal "row 3 of the copy", refused.diagnostics.detail
          assert_predicate c, :in_transaction?
          assert_equal [[10]], c.query("SELECT ID FROM BROKEN").rows
          c.query("ROLLBACK")

          assert_equal 1, c.copy_rows("BROKEN", %w[NAME ID], [["n", 4]])
          assert_equal [[4, "n"]], c.query("SELECT ID, NAME FROM BROKEN").rows
          c.query("COMMIT")
        end
      end

      # Verifies: [PROTOCOL CopyColumns 'O'] granted columns, rows by column:
      # nulls and empty strings kept apart; CopyData and CopyColumns mixed
      # in one copy, a row of a Float by row, the rows in order; each cell
      # cast as a character string of CopyData would be.
      # Verifies: [PROTOCOL Capabilities] columns granted, as every
      # connection asks it by default.
      # Verifies: [CLIENT Copying and exporting] a copy by column, by row
      # where not granted, to the same rows.
      def test_a_copy_by_column
        connect do |c|
          c.query("CREATE TABLE LANES (ID INTEGER, NAME VARCHAR(3), PAY DECIMAL(5,1), OK BOOLEAN)")
          c.query("COMMIT")
          rows = [["1", "", "1.5", "TRUE"], ["2", nil, nil, nil], [3, "abc", 2.5, false], ["4", "d", "3", "FALSE"]]

          assert c.granted?(Protocol::Capabilities::COLUMNS)
          assert_equal 4, c.copy_rows("LANES", %w[ID NAME PAY OK], rows)
          read = c.query("SELECT ID, NAME, PAY, OK FROM LANES ORDER BY ID").rows
          connect(offer: without(Protocol::Capabilities::COLUMNS)) do |by_row|
            by_row.query("DELETE FROM LANES")

            assert_equal 4, by_row.copy_rows("LANES", %w[ID NAME PAY OK], rows)
            assert_equal read, by_row.query("SELECT ID, NAME, PAY, OK FROM LANES ORDER BY ID").rows
            by_row.query("ROLLBACK")
          end

          assert_equal [[1, "", BigDecimal("1.5"), true], [2, nil, nil, nil]], read.first(2)
          c.query("COMMIT")
        end
      end

      # Verifies: [PROTOCOL CopyColumns 'O'] a cell too long failing at
      # CopyEnd with its row in the detail, never cut, every row undone; a
      # copy by column abandoned, none inserted.
      def test_a_copy_by_column_refused_and_abandoned
        connect do |c|
          c.query("CREATE TABLE NARROW (ID INTEGER, NAME VARCHAR(3))")
          c.query("COMMIT")
          too_long = assert_fails([-301, "22001"]) { c.copy_rows("NARROW", %w[ID NAME], [%w[5 ok], %w[6 long]]) }

          assert_equal "row 2 of the copy", too_long.diagnostics.detail
          assert_equal 0, c.copy_in("NARROW", %w[ID NAME]) { |copy| copy << %w[7 x] and copy.abandon }
          assert_equal [[0]], c.query("SELECT COUNT(*) FROM NARROW").rows
        end
      end

      # Verifies: [CLIENT Copying and exporting] an export as CSV, a header
      # then a record for each row, each value as turborel shows it; as the
      # protocol's own frames, read back with every value as it was.
      def test_exports
        connect do |c|
          sql = "VALUES (CAST(1.5 AS DECIMAL(5,2)), 'a,b', CAST(NULL AS INTEGER), '', DATE '2026-11-19', " \
                "ARRAY[1, 2], CAST(2.5 AS DOUBLE PRECISION))"
          out = StringIO.new

          assert_equal 1, c.export(sql, out)
          assert_equal "1.50,\"a,b\",,\"\",2026-11-19,\"ARRAY[1, 2]\",2.5E0\r\n", out.string.lines.last
          native = StringIO.new
          c.export(sql, native, :native)
          columns, rows = Export.read_native(native.string)

          assert_equal c.query(sql).rows, rows
          assert_equal 7, columns.size
        end
      end

      # Verifies: [PROTOCOL Lob 'L'] a character large object's octets
      # checked as UTF-8 as each Append comes: one that is not refused by
      # its Append (22021), every later one refused too.
      def test_appends_checked_as_utf8
        connect do |c|
          writer = c.create_lob(:character)
          writer << "fine"
          writer.flush

          assert_fails([-301, "22021"]) { c.lob_append(writer.instance_variable_get(:@locator), "\xFF".b) }
          assert_fails([-301, "22021"]) { c.lob_append(writer.instance_variable_get(:@locator), "more") }
          c.query("ROLLBACK")
        end
      end
    end
  end
end
