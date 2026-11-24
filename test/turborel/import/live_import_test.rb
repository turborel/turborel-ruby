# frozen_string_literal: true

require "stringio"
require "test_helper"
require_relative "../../server/live_server"

module Turborel
  module Import
    # Imports into a live server (RULES.md R-TEST-8), the cases of
    # turborel's own tests of its import, skipped without one.
    class LiveImportTest < Minitest::Test
      include TestSupport
      include LiveServer::Case

      # A source of records the program gives, typed or not.
      class Given
        def initialize(names, records)
          @headings = names.map { |name| Heading.new(name:, type: nil) }
          @records = records
          @next = 0
        end

        attr_reader :headings

        def record
          values = @records[@next] or return nil
          @next += 1
          Record.new(values:, position: Position.new(record: @next, line: nil))
        end
      end

      # A fresh table +name+ of STAFF's columns: ID its key, NAME, HIRED,
      # PAY DECIMAL(8,2) DEFAULT 1.
      def staff(connection, name)
        connection.query("CREATE TABLE #{name} (ID INTEGER NOT NULL PRIMARY KEY, NAME VARCHAR(20), HIRED DATE, " \
                         "PAY DECIMAL(8,2) DEFAULT 1)")
        connection.query("COMMIT")
      end

      # +text+ imported as +dialect+ says: what it did and the rows skipped,
      # or the import's failure.
      def csv(connection, text, dialect, options)
        skipped = []
        done = Import.run(connection, Delimited.new(StringIO.new(text), dialect), options) { skipped << _1 }
        [done, skipped]
      rescue ImportError => e
        [e, skipped]
      end

      # The rows of +table+, as text, by ID; the transaction ended.
      def table(connection, name)
        result = connection.query("SELECT ID, NAME, HIRED, PAY FROM #{name} ORDER BY ID")
        connection.query("COMMIT")
        result.rows.map { |row| row.each_with_index.map { |v, i| Text.of(v, result.columns[i].type) }.join(",") }
      end

      def into(name, batch: DEFAULT_BATCH, skip: false) = Options.new(table: name, batch:, skip:)

      # Verifies: [CLIENT Importing] a source's records go into the table,
      # each field into the column its heading names, or without headings
      # into the table's columns in order; each value cast to its column's
      # type, a null null, a column not named its default; the table named
      # in any way a <table name> may be; a batch committed at a time.
      def test_an_import_inserts_a_sources_records
        connect do |c|
          staff(c, "STAFF1")
          headed = "name,\"ID\",hired\nAda,1,1980-01-02\n\"Hopper, Grace\",2,\n"
          done, skipped = csv(c, headed, Dialect.csv.with_header, into("STAFF1", batch: 1))

          assert_equal [Imported.new(rows: 2, rejected: 0), []], [done, skipped]
          refute_predicate c, :in_transaction?
          assert_equal 2, csv(c, "3\tEve\t\\N\t12.5\n4\t\t1999-12-31\t\\N\n", Dialect.tsv.with_null("\\N"),
                              into("ann.staff1")).first.rows
          assert_equal 1, csv(c, "5,Bob,,2\n", Dialect.csv, into("\"ANN\" . \"STAFF1\"")).first.rows
          assert_equal ["1,Ada,1980-01-02,1.00", "2,Hopper, Grace,NULL,1.00", "3,Eve,NULL,12.50",
                        "4,,1999-12-31,NULL", "5,Bob,NULL,2.00"], table(c, "STAFF1")
          assert_equal Imported.new(rows: 0, rejected: 0), csv(c, "", Dialect.csv, into("STAFF1")).first
        end
      end

      # Verifies: [CLIENT Importing] a row the server refuses stops the
      # import, saying its record and line, the server's failure, the rows
      # committed and the batch rolled back; so does a record of too many
      # or too few fields, and one the source cannot read.
      def test_an_import_stops_at_a_bad_row
        connect do |c|
          staff(c, "STAFF2")
          stopped, = csv(c, "ID,NAME\n1,a\n2,b\n3,c\nfour,d\n5,e\n", Dialect.csv.with_header, into("STAFF2", batch: 2))

          assert_equal [Position.new(record: 4, line: 5), "22018", -301, 2, 1],
                       [stopped.position, stopped.sqlstate, stopped.sqlcode, stopped.committed, stopped.rolled_back]
          assert_match(/\Arecord 4, line 5: SQLCODE -301 \(SQLSTATE 22018\): .*; 2 rows committed, 1 rolled back\z/,
                       stopped.message)
          refute_predicate c, :in_transaction?
          assert_equal ["1,a,NULL,1.00", "2,b,NULL,1.00"], table(c, "STAFF2")
          stopped_more(c)
        end
      end

      # A short record, one unread, and a duplicate each stop the import.
      def stopped_more(connection)
        short, = csv(connection, "6,f,,1\n7,g\n", Dialect.csv, into("STAFF2", batch: 0))

        assert_equal "record 2, line 2: 2 fields, for 4 columns; 0 rows committed, 1 rolled back", short.message
        unread, = csv(connection, "ID\n8\n\"9\n", Dialect.csv.with_header, into("STAFF2", batch: 0))

        assert_equal "record 2, line 3: [RFC 4180 §2 rule 5] a quoted field is not closed; 0 rows committed, " \
                     "1 rolled back", unread.message
        assert_equal "23000",
                     csv(connection, "ID\n1\n", Dialect.csv.with_header, into("STAFF2", batch: 0)).first.sqlstate
        assert_equal 2, table(connection, "STAFF2").size
      end

      # Verifies: [CLIENT Importing] told to skip bad rows, an import
      # reports each, its record, line and why, and inserts the rest.
      def test_an_import_skips_bad_rows_when_asked
        connect do |c|
          staff(c, "STAFF3")
          done, skipped = csv(c, "ID,NAME\n1,a\nx,b\n3\n1,again\n5,e\n", Dialect.csv.with_header,
                              into("STAFF3", batch: 2, skip: true))

          assert_equal Imported.new(rows: 2, rejected: 3), done
          assert_match(/\Arecord 2, line 3: SQLCODE -301 \(SQLSTATE 22018\): .*; skipped\z/, skipped[0].to_s)
          assert_equal "record 3, line 4: 1 fields, for 2 columns; skipped", skipped[1].to_s
          assert_equal Position.new(record: 4, line: 5), skipped[2].position
          assert_equal ["1,a,NULL,1.00", "5,e,NULL,1.00"], table(c, "STAFF3")
          done, skipped = csv(c, "ID\n1\n", Dialect.csv.with_header, into("STAFF3", batch: 0, skip: true))

          assert_equal [Imported.new(rows: 0, rejected: 1), 1, false], [done, skipped.size, c.in_transaction?]
        end
      end

      # Verifies: [CLIENT Importing] an import is refused before any row in a
      # transaction active; of a table not named as a <table name>, nor one
      # that exists; of headings naming no column of it; of a source whose
      # headings cannot be read.
      def test_an_import_is_refused_before_any_row
        connect do |c|
          staff(c, "STAFF4")
          c.query("INSERT INTO STAFF4 (ID) VALUES (1)")
          active, = csv(c, "2\n", Dialect.csv, into("STAFF4"))

          assert_equal "an import begins with no transaction active, as it commits its batches; 0 rows committed, " \
                       "0 rolled back", active.message
          assert_predicate c, :in_transaction?
          c.query("ROLLBACK")
          refused_tables(c)

          missing = csv(c, "2\n", Dialect.csv, into("NOPE")).first

          assert_equal [-103, "42000"], [missing.sqlcode, missing.sqlstate]
          assert_match(/WAGE/, csv(c, "ID,WAGE\n2,3\n", Dialect.csv.with_header, into("STAFF4")).first.message)
          assert_equal Position.new(record: 0, line: 1),
                       csv(c, "", Dialect.csv.with_header, into("STAFF4")).first.position
          assert_empty table(c, "STAFF4")
        end
      end

      # Tables named wrong, each refused saying so.
      def refused_tables(connection)
        ["STAFF; DROP TABLE STAFF", "1STAFF", "A.B.C.D", "X.", "'STAFF'", ""].each do |wrong|
          refused, = csv(connection, "2\n", Dialect.csv, into(wrong))

          assert_equal ["[ISO/IEC 9075:1992 §5.4] #{wrong} is not a <table name>", true],
                       [refused.failure.message, refused.input]
        end
      end

      # Verifies: [CLIENT Importing] a commit of a batch that fails, a
      # deferred constraint not satisfied, stops the import, the batch
      # rolled back.
      def test_a_batch_whose_commit_fails
        connect do |c|
          c.query("CREATE TABLE U (K INTEGER UNIQUE DEFERRABLE INITIALLY DEFERRED)")
          c.query("COMMIT")
          stopped = assert_raises(ImportError) do
            Import.run(c, Delimited.new(StringIO.new("1\n2\n3\n3\n")), into("U", batch: 2))
          end

          assert_equal [nil, "40002", 2, 2],
                       [stopped.position, stopped.sqlstate, stopped.committed, stopped.rolled_back]
          assert_equal [[1], [2]], c.query("SELECT K FROM U ORDER BY K").rows
          c.query("COMMIT")
        end
      end

      # Verifies: [CLIENT Importing] a CSV source larger than any batch
      # streams a record at a time, many batches of it committed.
      def test_a_large_source_streams
        connect do |c|
          staff(c, "STAFF5")
          text = "ID,NAME\n#{(1..20_000).map { |n| "#{n},\"#{"x" * 20}\"\n" }.join}"
          done, = csv(c, text, Dialect.csv.with_header.with_max_record(256), into("STAFF5", batch: 5_000))

          assert_equal 20_000, done.rows
          assert_equal [[20_000, 1, 20_000]], c.query("SELECT COUNT(*), MIN(ID), MAX(ID) FROM STAFF5").rows
          c.query("COMMIT")
        end
      end

      # Verifies: [CLIENT Importing] a string for a character string column
      # is assigned as INSERT assigns: one too long refused (22001), not
      # cut, spaces past the length cut.
      def test_a_string_too_long_is_refused
        connect do |c|
          c.query("CREATE TABLE T (K INTEGER, F CHARACTER(3), V VARCHAR(3))")
          c.query("COMMIT")
          done, skipped = csv(c, "1,ab,abc   \n2,abcd,a\n3,a,abcd\n", Dialect.csv, into("T", skip: true))

          assert_equal Imported.new(rows: 1, rejected: 2), done
          assert_equal([[2, "22001"], [3, "22001"]], skipped.map { [_1.position.record, _1.failure.sqlstate] })
          assert(skipped.all? { _1.failure.rule.start_with?("ISO/IEC 9075:1992 §13.8 GR4b iii, §9.2 GR3") })
          assert_equal [["ab |", "abc|"]], c.query("SELECT F || '|', V || '|' FROM T").rows
          c.query("COMMIT")
        end
      end

      # Verifies: [CLIENT Large objects] an import's field longer than 64
      # KiB for a CLOB or BLOB column sent by creating a large object, a
      # short one and a null as they are; character and binary alike.
      def test_large_objects_by_their_locators
        connect do |c|
          c.query("CREATE TABLE IDOCS (ID INTEGER, C CLOB(1M), B BLOB(1M))")
          c.query("COMMIT")
          source = Given.new(%w[ID C B], [[1, "é" * 35_000, ("\x07" * 70_000).b], [2, "short", nil]])

          assert_equal 2, Import.run(c, source, into("IDOCS")).rows
          assert_equal [[1, 35_000, 70_000, 70_000], [2, 5, 5, nil]],
                       c.query("SELECT ID, CHAR_LENGTH(C), OCTET_LENGTH(C), OCTET_LENGTH(B) FROM IDOCS " \
                               "ORDER BY ID").rows
          long = "1,#{"a" * 600_000}\n"
          c.query("CREATE TABLE LONGDOC (K INTEGER, C CLOB(1M))")
          c.query("COMMIT")

          assert_equal 1, csv(c, long, Dialect.csv.with_max_record(700_000), into("LONGDOC")).first.rows
          assert_equal [[1, 600_000]], c.query("SELECT K, CHAR_LENGTH(C) FROM LONGDOC").rows
          c.query("COMMIT")
        end
      end

      # Verifies: [CLIENT Importing] a heading that is a key word names the
      # column of its name in upper case; one that is no identifier names
      # the column of its text as written; a record of too few fields stops
      # an import or is skipped; a value its column cannot be cast to
      # stops it with the server's failure.
      def test_headings_and_short_records
        connect do |c|
          c.query("CREATE TABLE ODD (\"VALUE\" INTEGER, \"two words\" INTEGER)")
          c.query("CREATE TABLE P (A INTEGER, B INTEGER)")
          c.query("COMMIT")

          assert_equal 1, Import.run(c, Given.new(["value", "two words"], [[1, 2]]), into("ODD")).rows
          records = [[1, 1], [2], [3, 3]]
          stopped = assert_raises(ImportError) { Import.run(c, Given.new(%w[A B], records), into("P")) }

          assert_equal [Position.new(record: 2, line: nil), true, 0, 1],
                       [stopped.position, stopped.input, stopped.committed, stopped.rolled_back]
          skipped = []
          done = Import.run(c, Given.new(%w[A B], records), into("P", skip: true)) { skipped << _1 }

          assert_equal [2, 1, [2]], [done.rows, done.rejected, skipped.map { _1.position.record }]
          wrong = assert_raises(ImportError) { Import.run(c, Given.new(%w[A], [[true]]), into("P")) }

          assert_equal [-301, "22005"], [wrong.sqlcode, wrong.sqlstate]
        end
      end

      # Verifies: [CLIENT Importing] through an INSERT, a table with a large
      # object column: a bad row stopping the import, its batch rolled back;
      # a record the source cannot read; a commit that fails.
      def test_an_import_by_insert_stops
        connect do |c|
          c.query("CREATE TABLE NOTE2 (ID INTEGER PRIMARY KEY, BODY CLOB(1M))")
          c.query("CREATE TABLE NOTE3 (ID INTEGER UNIQUE DEFERRABLE INITIALLY DEFERRED, BODY CLOB(1M))")
          c.query("COMMIT")
          bad, = csv(c, "1,a\n2,b\nx,c\n", Dialect.csv, into("NOTE2", batch: 1))

          assert_equal [Position.new(record: 3, line: 3), "22018", 2, 0],
                       [bad.position, bad.sqlstate, bad.committed, bad.rolled_back]
          unread, = csv(c, "3,a\n\"4,b\n", Dialect.csv, into("NOTE2", batch: 0))

          assert_equal [Position.new(record: 2, line: 2), true, 1], [unread.position, unread.input, unread.rolled_back]
          commit, = csv(c, "1,a\n1,b\n", Dialect.csv, into("NOTE3", batch: 0))

          assert_equal ["40002", nil], [commit.sqlstate, commit.position]
          refute_predicate c, :in_transaction?
        end
      end
    end
  end
end
