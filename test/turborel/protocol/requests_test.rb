# frozen_string_literal: true

require "test_helper"

module Turborel
  module Protocol
    # Every request the client sends, encoded.
    class RequestsTest < Minitest::Test
      include TestSupport

      # Verifies: [PROTOCOL A worked example] the Hello of trust as ANN
      # asking for ping is these 41 bytes, with no tail.
      def test_hello_is_the_worked_examples_bytes
        hello = Requests.hello(user: "ANN", mechanism: "trust", initial: "", capabilities: ["ping"])

        assert_equal hex("48 24000000 01000000 03000000 414E4E 05000000 7472757374 00000000 " \
                         "01000000 04000000 70696E67"),
                     hello
        assert_equal 41, hello.bytesize
      end

      # Verifies: [PROTOCOL Hello 'H'] Hello carries version 1, the user, the
      # mechanism, its first bytes, the capabilities, and tail 1, the
      # connection's attributes.
      def test_hello_carries_its_attributes
        hello = Requests.hello(user: "A", mechanism: "m", initial: "\x01", capabilities: [],
                               attributes: [%w[application x]])

        assert hello.end_with?(writer.u8(1).u32(1).str("application").str("x").to_s)
        assert_equal Requests::VERSION, hello.byteslice(5, 4).unpack1("V")
      end

      # Verifies: [PROTOCOL Answer 'A'] Answer is bytes, the client's answer
      # to a Challenge.
      def test_answer
        assert_equal hex("41 07000000 03000000 633D31"), Requests.answer("c=1")
        assert_equal hex("41 04000000 00000000"), Requests.answer("")
      end

      # Verifies: [PROTOCOL A worked example] the Query of VALUES 1 with ends
      # set, and Ping, a header alone.
      def test_query_and_ping_are_the_worked_examples_bytes
        assert_equal hex("51 0D000000 08000000 56414C5545532031 01"), Requests.query("VALUES 1", ends: true)
        assert_equal hex("47 00000000"), Requests.ping
      end

      # Verifies: [PROTOCOL Query 'Q'] Query is sql, the ends flag, then tail
      # 1, attributes, and 2, multi, in that order, each only where set.
      def test_query_tail
        assert_equal hex("51 08000000 02000000 4142 00 02"), Requests.query("AB", ends: false, multi: true)
        with_both = Requests.query("A", ends: true, attributes: [%w[a b]], multi: true)

        assert with_both.end_with?(writer.u8(1).u32(1).str("a").str("b").u8(2).to_s)
      end

      # Verifies: [PROTOCOL Execute 'E'] Execute is statement, a row of
      # values, rows, the ends flag, then tail 1 and 3, the cursor, written
      # only if it is not 0.
      def test_execute
        plain = Requests.execute(4, [nil, "é"], rows: 10, ends: false)
        body = writer.u32(4).u32(2).u8(0).u8(1).str("é").u32(10).flag(false).to_s

        assert_equal Frame.encode(Requests::EXECUTE, body), plain
        numbered = Requests.execute(4, [], rows: 0, ends: true, tail: { attributes: [%w[a b]], cursor: 2 })

        assert numbered.end_with?(writer.u8(1).u32(1).str("a").str("b").u8(3).u32(2).to_s)
      end

      # Verifies: [PROTOCOL Fetch 'F'] Fetch, Close and Deallocate carry the
      # statement, Fetch its rows, Fetch and Close tail 3 of a cursor not 0.
      def test_fetch_close_and_deallocate
        assert_equal hex("46 08000000 02000000 FFFFFFFF"), Requests.fetch(2, rows: 0xFFFF_FFFF)
        assert_equal hex("46 0D000000 02000000 01000000 03 05000000"), Requests.fetch(2, rows: 1, cursor: 5)
        assert_equal hex("43 04000000 03000000"), Requests.close(3)
        assert_equal hex("43 09000000 03000000 03 01000000"), Requests.close(3, cursor: 1)
        assert_equal hex("44 04000000 04000000"), Requests.deallocate(4)
        assert_equal hex("50 0D000000 01000000 05000000 56414C5545"), Requests.prepare(1, "VALUE")
      end

      # Verifies: [PROTOCOL Lob 'L'] the request: op u8, then read's locator,
      # from, count and characters flag; create's kind; append's locator and
      # bytes; free's and hold's locator.
      def test_lob_requests
        assert_equal hex("4C 16000000 00 07000000 0100000000000000 0200000000000000 01"),
                     Requests.lob_read(7, 1, 2, characters: true)
        assert_equal hex("4C 02000000 01 01"), Requests.lob_create(:binary)
        assert_equal hex("4C 0A000000 02 07000000 01000000 41"), Requests.lob_append(7, "A")
        assert_equal hex("4C 05000000 03 07000000"), Requests.lob_free(7)
        assert_equal hex("4C 05000000 04 07000000"), Requests.lob_hold(7)
        assert_fails(UNSUPPORTED) { Requests.lob_create(:text) }
      end

      # Verifies: [PROTOCOL Cancel 'Z'] Cancel is the key alone, 16 bytes with
      # no length; Terminate, Reset and Ping are headers alone.
      def test_cancel_and_headers_alone
        key = "\x07".b * 16

        assert_equal hex("5A 10000000") + key, Requests.cancel(key)
        assert_fails(OUT_OF_RANGE) { Requests.cancel("\x07" * 15) }
        assert_equal hex("58 00000000"), Requests.terminate
        assert_equal hex("57 00000000"), Requests.reset
      end

      # Verifies: [PROTOCOL Describe 'Y'] Describe is what u8, 0 a statement
      # and 1 a cursor, the statement, and the cursor, 0 of a statement.
      def test_describe
        assert_equal hex("59 09000000 00 02000000 00000000"), Requests.describe_statement(2)
        assert_equal hex("59 09000000 01 02000000 03000000"), Requests.describe_cursor(2, 3)
      end

      # Verifies: [PROTOCOL ChangeUser 'U'] ChangeUser is the user, the
      # mechanism and its first bytes.
      def test_change_user
        assert_equal Frame.encode(Requests::CHANGE_USER, writer.str("B").str("trust").bytes("").to_s),
                     Requests.change_user("B", "trust", "")
      end

      # Verifies: [PROTOCOL CopyData 'J'] CopyData is a list of rows, as many
      # at a time as the client likes.
      def test_copy_data
        assert_equal hex("4A 04000000 00000000"), Requests.copy_data([])
        assert_equal hex("4A 0F000000 02000000 01000000 00 01000000 0E 01"), Requests.copy_data([[nil], [true]])
      end

      # Verifies: [PROTOCOL CopyIn 'I'] CopyIn is the table, its columns, none
      # for every column, and the ends flag; CopyEnd the abandon flag.
      def test_copy_requests
        assert_equal Frame.encode(Requests::COPY_IN, writer.str("T").strs(%w[ID NAME]).flag(true).to_s),
                     Requests.copy_in("T", %w[ID NAME], ends: true)
        assert_equal hex("4A 0F000000 02000000 01000000 00 01000000 0E 01"), Requests.copy_data([[nil], [true]])
        assert_equal hex("4E 01000000 01"), Requests.copy_end(abandon: true)
      end
    end
  end
end
