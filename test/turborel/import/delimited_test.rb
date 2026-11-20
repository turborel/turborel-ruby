# frozen_string_literal: true

require "stringio"
require "test_helper"

module Turborel
  module Import
    # Delimited text read a record at a time, as turborel-client's own
    # tests of it read it.
    class DelimitedTest < Minitest::Test
      include TestSupport

      def source(text, dialect = Dialect.csv) = Delimited.new(StringIO.new(text.b), dialect)

      def fields(text, dialect = Dialect.csv)
        reader = source(text, dialect)
        out = []
        while (record = reader.record)
          out << record.values
        end
        out
      end

      def error(text, dialect = Dialect.csv)
        assert_raises(SourceError) { fields(text, dialect) }
      end

      # Verifies: [CLIENT Importing] CSV: records at CR LF or LF, the last
      # optional; spaces kept; a field in quotes holding the delimiter, a
      # quote written twice and line breaks; an empty field null, "" the
      # empty string; text UTF-8.
      def test_csv_records_and_fields
        assert_equal [%w[a b], %w[c d]], fields("a,b\r\nc,d\n")
        assert_equal [%w[a b], %w[c d]], fields("a,b\nc,d")
        assert_equal [[" a ", " b "]], fields(" a , b ")
        assert_equal [["a,b", "say \"hi\""]], fields("\"a,b\",\"say \"\"hi\"\"\"")
        assert_equal [["one\r\ntwo\nthree", "x"]], fields("\"one\r\ntwo\nthree\",x\n")
      end

      # Verifies: [CLIENT Importing] an empty field null, "" the empty
      # string, an empty line a null; a quote written twice; no records of
      # no text; text UTF-8.
      def test_csv_empty_and_quoted_fields
        assert_equal [[nil, "", nil]], fields(",\"\",")
        assert_equal [["a"], [nil], ["b"]], fields("a\n\nb\n")
        assert_equal [["\""]], fields("\"\"\"\"")
        assert_empty fields("")
        assert_equal [["é", "\u{1F600}"]], fields("é,\u{1F600}")
      end

      # Verifies: [CLIENT Importing] a text for null, not in quotes; a byte
      # order mark passed over at the input's start alone.
      def test_null_text_and_byte_order_mark
        assert_equal [[nil, "NULL", "", "null"]], fields("NULL,\"NULL\",,null", Dialect.csv.with_null("NULL"))
        assert_equal [%w[a b], ["\u{FEFF}c"]], fields("\u{FEFF}a,b\n\u{FEFF}c")
      end

      # Verifies: [CLIENT Importing] a header names the fields, read once;
      # each record's position, its number and the line it began on; none
      # after the end; a header asked for but missing refused.
      def test_header_and_positions
        text = "ID,\"FULL NAME\"\n1,\"Ada\nLovelace\"\n2,Grace\n"
        reader = source(text, Dialect.csv.with_header)
        headings = reader.headings

        assert_equal([["ID", nil], ["FULL NAME", nil]], headings.map { [_1.name, _1.type] })
        assert_nil reader.headings
        positions = [reader.record, reader.record].map(&:position)

        assert_equal [Position.new(record: 1, line: 2), Position.new(record: 2, line: 4)], positions
        assert_nil reader.record
        assert_equal [%W[1 Ada\nLovelace], %w[2 Grace]], fields(text, Dialect.csv.with_header)
      end

      # Verifies: [CLIENT Importing] a header asked for but missing refused,
      # where it would be; none unless asked for.
      def test_header_missing
        missing = assert_raises(SourceError) { source("", Dialect.csv.with_header).headings }

        assert_equal ["record 0, line 1", "there is no header"], [missing.position.to_s, missing.message]
        assert_nil source("a").headings
        assert_equal "record 3", Position.new(record: 3, line: nil).to_s
      end

      # Verifies: [CLIENT Importing] a quote in a field not quoted, anything
      # but the delimiter after a closing quote, a quote left open and a
      # field not UTF-8 refused, saying where; nothing more after.
      def test_errors_say_where
        quote = error("a\nb,c\"d\n")

        assert_equal [Position.new(record: 2, line: 2),
                      "[RFC 4180 §2 rule 5] field 2: a quote in a field not enclosed in quotes"],
                     [quote.position, quote.message]
        assert_equal "[RFC 4180 §2 rule 5] field 1: a quoted field's closing quote is followed by more",
                     error("\"a\"b,c").message
        open = error("a\nb\n\"c\nd\ne\n")

        assert_equal [Position.new(record: 3, line: 3), "[RFC 4180 §2 rule 5] a quoted field is not closed"],
                     [open.position, open.message]
        assert_equal "[RFC 4180 §2 rule 5] a quoted field is not closed", error("\"c").message
        assert_equal "field 2 is not UTF-8", error("ok,\xFF\xFE").message
        assert_equal "field 2 is not UTF-8", error("ok\t\xFF", Dialect.tsv).message
        reader = source("\"a\"b\nc\n")
        assert_raises(SourceError) { reader.record }
        assert_nil reader.record
      end

      # Verifies: [CLIENT Importing] a record longer than the bound refused
      # once the bound is read, so endless input is read in bounded memory;
      # a record of the bound read, its line break counted; a reader's
      # failure told.
      def test_records_are_bounded
        endless = Object.new
        endless.define_singleton_method(:gets) { |_separator, limit| "a" * limit }

        assert_equal "the record is longer than 1024 bytes",
                     assert_raises(SourceError) {
                       Delimited.new(endless, Dialect.csv.with_max_record(1024)).record
                     }.message
        quotes = StringIO.new("#{"\"" * 10_000}\n")

        assert_raises(SourceError) { Delimited.new(quotes, Dialect.csv.with_max_record(4096)).record }
        assert_equal [["abcd"]], fields("abcd\n", Dialect.csv.with_max_record(5))
        assert_raises(SourceError) { fields("abcde\n", Dialect.csv.with_max_record(5)) }
        assert_equal 16 * 1024 * 1024, Delimited::DEFAULT_MAX_RECORD
        failing = Object.new
        failing.define_singleton_method(:gets) { |*| raise IOError, "the disk is gone" }

        assert_equal "cannot read: the disk is gone", assert_raises(SourceError) {
          Delimited.new(failing).record
        }.message
      end

      # Verifies: [CLIENT Importing] tab-separated text: fields at tabs,
      # never quoted; an empty field null; its own text for null.
      def test_tab_separated
        assert_equal [%w[a b], ["\"c", "\"d\""]], fields("a\tb\r\n\"c\t\"d\"\n", Dialect.tsv)
        assert_equal [["a", nil, "b,c"]], fields("a\t\tb,c", Dialect.tsv)
        assert_equal [["a", nil]], fields("a\t\\N", Dialect.tsv.with_null("\\N"))
      end

      # Verifies: [CLIENT Importing] a delimiter is one ASCII character, not
      # a quote, CR or LF; fields then split at it.
      def test_delimiters
        assert_equal [["a", "b;c", "d,e"]], fields("a;\"b;c\";d,e", Dialect.csv.with_delimiter(";"))
        assert_equal [%W[a b\tc]], fields("a|b\tc", Dialect.tsv.with_delimiter("|"))
        ["\"", "\n", "\r", "é", "ab", 1].each do |wrong|
          assert_fails(MISUSED) { Dialect.csv.with_delimiter(wrong) }
        end
      end
    end
  end
end
