# frozen_string_literal: true

require "test_helper"

module Turborel
  module Protocol
    # Every reply the client receives, decoded.
    class RepliesTest < Minitest::Test
      include TestSupport

      def reply(frame)
        kind, length = Frame.decode_header(frame.byteslice(0, Frame::HEADER_BYTES) || "")
        Replies.decode(kind, frame.byteslice(Frame::HEADER_BYTES, length) || "")
      end

      def frame(kind, body) = Frame.encode(kind.ord, body)

      # Verifies: [PROTOCOL A worked example] the Rows reply of one row of the
      # exact number 1, and the Complete of an empty tail.
      def test_worked_examples_replies
        assert_equal Replies::Rows.new(rows: [[1]]),
                     reply(hex("42 1D000000 01000000 01000000 02 01#{"00" * 15} 00000000"))
        complete = reply(hex("4B 0E000000 00000000 05000000 3030303030 00"))

        assert_equal [0, "00000", false], [complete.sqlcode, complete.sqlstate, complete.active]
        assert_equal [nil, false, nil, [], [], nil],
                     [complete.position, complete.more, complete.rows, complete.generated, complete.conditions,
                      complete.time]
      end

      # Verifies: [PROTOCOL A worked example] with row-counts, the same
      # Complete ends with tag 6 and the row count, then tag 18 and the
      # server's three times.
      def test_worked_examples_complete_with_row_counts
        tail = "06 0100000000000000 12 B400000000000000 0400000000000000 0000000000000000"
        complete = reply(hex("4B 30000000 00000000 05000000 3030303030 00 #{tail}"))

        assert_equal 1, complete.rows
        assert_equal Replies::Timing.new(total: 180, queued: 4, locks: 0), complete.time
      end

      # Verifies: [PROTOCOL Complete 'K'] Complete is SQLCODE as u32,
      # SQLSTATE, the active flag, then tags 4, 5, 6, 16, 17 and 18 in order,
      # a condition a failure as bytes.
      def test_complete_with_every_tag
        condition = writer.u32(0).str("01000").str("warned").flag(false).flag(false).flag(true)
                          .u8(7).str("WARNING").to_s
        body = writer.u32(100).str("02000").flag(true).u8(4).u64(4711).u8(5).u8(6).u64(2).u8(16).strs(%w[3 4])
                     .u8(17).u32(1).bytes(condition).u8(18).u64(1).u64(2).u64(3).to_s
        complete = reply(frame("K", body))

        assert_equal [100, "02000", true], [complete.sqlcode, complete.sqlstate, complete.active]
        assert_equal [4711, true, 2, %w[3 4]], [complete.position, complete.more, complete.rows, complete.generated]
        assert_equal ["01000", "warned", true, "WARNING"],
                     complete.conditions.map { |f| [f.sqlstate, f.message, f.active, f.diagnostics&.severity] }.first
        assert_fails { reply(frame("K", writer.u32(0).str("00000").flag(false).u8(6).u64(1).u8(4).u64(1).to_s)) }
        assert_fails { reply(frame("K", writer.u32(0).str("00000").flag(false).u8(7).str("x").to_s)) }
      end

      # Verifies: [PROTOCOL Challenge 'C'] Challenge is bytes, the next step
      # of an exchange.
      def test_challenge
        assert_equal Replies::Challenge.new(challenge: "r=1".b), reply(frame("C", writer.bytes("r=1").to_s))
      end

      # Verifies: [PROTOCOL Ready 'R'] Ready is the authorization, a 16-byte
      # key with no length, the capabilities and the server's product.
      def test_ready
        key = "\x05".b * 16
        ready = reply(frame("R", writer.str("ANN").raw(key).strs(%w[ping]).str("turborel 0.0.0 (alpha)").to_s))

        server = "turborel 0.0.0 (alpha)"

        assert_equal Replies::Ready.new(authorization: "ANN", key:, capabilities: %w[ping], server:), ready
      end

      # Verifies: [PROTOCOL Prepared 'P'] Prepared is the statement, its
      # parameters in the order of their marks, and its columns.
      def test_prepared_and_description
        parameter = writer.flag(true).u8(5).u32(0xFFFF_FFFF).u8(0).to_s
        column = writer.flag(true).str("ID").u8(2).u32(10).u32(0).flag(true).to_s
        prepared = reply(frame("P", writer.u32(1).u32(1).raw(parameter).u32(1).raw(column).to_s))

        assert_equal 1, prepared.statement
        assert prepared.parameters.first&.varying
        exact = DataType.new(kind: :exact, params: { precision: 10, scale: 0 })

        assert_equal Column.new(name: "ID", type: exact, not_null: true), prepared.columns.first
      end

      # Verifies: [PROTOCOL Description 'D'] Description is a list of columns.
      def test_description
        unnamed = reply(frame("D", writer.u32(1).flag(false).u8(14).flag(false).to_s))

        assert_nil unnamed.columns.first&.name
        assert_equal Replies::Description.new(columns: []), reply(hex("44 04000000 00000000"))
      end

      # Verifies: [PROTOCOL Rows 'B'] Rows is a batch of rows, each a list of
      # values.
      def test_rows
        body = writer.u32(2).u32(2).u8(0).u8(1).str("a").u32(0).to_s

        assert_equal Replies::Rows.new(rows: [[nil, "a"], []]), reply(frame("B", body))
      end

      # Verifies: [PROTOCOL Error 'E'] Error is a failure, SQLCODE i32 as
      # u32, SQLSTATE, message, rule, position, active, and with diagnostics
      # tags 7 to 15.
      def test_error_reply
        body = writer.u32(0xFFFF_FF37).str("23000").str("broken").flag(true).str("ISO 1").flag(true).u64(7).flag(true)
                     .u8(7).str("ERROR").u8(12).str("T").u8(15).str("K").to_s
        failure = reply(frame("E", body)).failure

        assert_equal [-201, "23000", "broken", "ISO 1", 7, true], [failure.sqlcode, failure.sqlstate, failure.message,
                                                                   failure.rule, failure.position, failure.active]
        assert_equal ["ERROR", "T", "K", nil], [failure.diagnostics&.severity, failure.diagnostics&.table,
                                                failure.diagnostics&.constraint, failure.diagnostics&.hint]
        bare = reply(frame("E",
                           writer.u32(0).str("08006").str("lost").flag(false).flag(false).flag(false).to_s)).failure

        assert_nil bare.diagnostics
      end

      # Verifies: [PROTOCOL Notice 'N'] Notice is SQLSTATE, message and tags
      # 7 to 15.
      def test_notice
        notice = reply(frame("N", writer.str("01T01").str("rolled back").u8(7).str("NOTICE").to_s))

        assert_equal ["01T01", "rolled back", "NOTICE"], [notice.sqlstate, notice.message, notice.diagnostics&.severity]
        assert_nil reply(frame("N", writer.str("01000").str("w").to_s)).diagnostics
      end

      # Verifies: [PROTOCOL Status 'T'] Status is a setting's name and its
      # value as SQL writes it, empty for a null.
      def test_status
        status = reply(frame("T", writer.str("SERVER_READ_ONLY").str("NO").to_s))

        assert_equal Replies::Status.new(name: "SERVER_READ_ONLY", value: "NO"), status
        assert_equal "", reply(frame("T", writer.str("SCHEMA").str("").to_s)).value
      end

      # Verifies: [PROTOCOL Suspended 'S'] Suspended is a header alone.
      def test_suspended
        assert_equal Replies::Suspended.new, reply(hex("53 00000000"))
      end

      # Verifies: [PROTOCOL Pong 'G'] Pong is a header alone.
      def test_pong
        assert_equal Replies::Pong.new, reply(hex("47 00000000"))
      end

      # Verifies: [PROTOCOL Lob 'L'] the reply: what u8, 0 data and its bytes,
      # 1 a locator u32.
      def test_lob_replies
        assert_equal Replies::LobData.new(data: "AB".b), reply(hex("4C 07000000 00 02000000 4142"))
        assert_equal Replies::LobLocator.new(locator: 9), reply(hex("4C 05000000 01 09000000"))
        assert_fails { reply(hex("4C 01000000 02")) }
      end

      # Verifies: [PROTOCOL Frames] a kind is read in the direction it
      # travels: C from the server is Challenge, which from a client is
      # Close; a kind no reply has fails the connection.
      def test_kinds_are_read_as_replies
        assert_kind_of Replies::Challenge, reply(frame("C", writer.bytes("").to_s))
        assert_equal "C".ord, Requests::CLOSE
        %w[A Q F X Z].each { |kind| assert_fails { reply(frame(kind, "")) } }
      end

      # Verifies: [PROTOCOL Frames] a body cut short, or bytes left over after
      # the last field, fails the connection.
      def test_bodies_cut_short_or_left_over_fail
        assert_fails { reply(hex("47 01000000 00")) }
        assert_fails { reply(frame("T", writer.str("A").to_s)) }
        assert_fails { reply(frame("C", writer.bytes("").u8(0).to_s)) }
      end
    end
  end
end
