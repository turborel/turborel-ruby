# frozen_string_literal: true

require "stringio"
require "test_helper"
require_relative "../../support/fake_server"

module Turborel
  module Client
    # Copies and exports, against a server of the test's own script.
    class CopyTest < Minitest::Test
      include TestSupport

      # Every capability but compression, so frames come as they are, and
      # columns, so rows go by row.
      GRANTED = Protocol::Capabilities::ALL - [Protocol::Capabilities::COMPRESSION, Protocol::Capabilities::COLUMNS]
      # Those and columns, so rows go by column where they can.
      BY_COLUMN = GRANTED + [Protocol::Capabilities::COLUMNS]

      # A Complete's tail 6 of +rows+.
      def counted(rows) = Protocol::Writer.new.u8(6).u64(rows).to_s

      # Runs +script+ after login granting +granted+, then reads Terminate;
      # gives the connection and the server.
      def scripted(granted = GRANTED, &)
        server = FakeServer.new do |peer|
          peer.frame
          peer.ready(granted)
          frames = []
          yield(peer, frames)
          frames << peer.frame
          frames
        end
        [Client.connect_to(server.target, user: "ann", mechanism: Trust.new), server]
      end

      # Verifies: [PROTOCOL CopyIn 'I'] CopyIn of a table, its columns and
      # ends; rows sent many to a CopyData with no reply; until CopyEnd only
      # CopyData, CopyColumns, CopyEnd and Ping sent, anything else refused
      # before it is sent (TB910).
      def test_copy_in
        connection, server = scripted do |peer, frames|
          2.times { frames << peer.frame }
          peer.reply("G")
          2.times { frames << peer.frame }
          peer.complete(0, "00000", tail: counted(2))
        end
        copy = connection.copy_in("STAFF", %w[ID NAME])
        copy << [7, "Niklaus"]
        copy << [8, "Barbara"]

        assert_fails(MISUSED) { connection.query("VALUES 1") }
        connection.ping

        assert_equal 2, copy.finish
        ended(copy)
        connection.terminate
        begin_copy, ping, data, finish = server.join

        assert_equal Protocol::Requests.copy_in("STAFF", %w[ID NAME], ends: false), Protocol::Frame.encode(*begin_copy)
        assert_equal ["G".ord, "J".ord], [ping.first, data.first]
        assert_equal Protocol::Requests.copy_data([[7, "Niklaus"], [8, "Barbara"]]), Protocol::Frame.encode(*data)
        assert_equal Protocol::Requests.copy_end(abandon: false), Protocol::Frame.encode(*finish)
      end

      # A copy ended takes no more.
      def ended(copy)
        assert_fails(MISUSED) { copy << [9, "late"] }
        assert_fails(MISUSED) { copy.finish }
        assert_fails(MISUSED) { copy.abandon }
      end

      # Verifies: [PROTOCOL Ping 'G'] Ping answered by Pong at any point
      # after Ready, during a copy too, the copy going on.
      def test_ping_during_a_copy
        connection, server = scripted do |peer, frames|
          frames << peer.frame
          peer.reply("G")
          2.times { frames << peer.frame }
          peer.reply("G")
          frames << peer.frame
          peer.complete(0, "00000", tail: counted(0))
        end
        connection.ping
        copy = connection.copy_in("T")

        assert_nil connection.ping
        assert_equal 0, copy.finish
        connection.terminate

        assert_equal ["G".ord, "I".ord, "G".ord, "N".ord, "X".ord], server.join.map(&:first)
      end

      # Verifies: [PROTOCOL CopyEnd 'N'] rows past a chunk go in a CopyData
      # of their own; abandon 1 undoes every row, the Complete counting
      # none; under autocommit the copy ends its transaction.
      def test_chunks_abandon_and_ends
        big = "x" * Copy::CHUNK_BYTES
        connection, server = scripted do |peer, frames|
          3.times { frames << peer.frame }
          peer.complete(0, "00000", tail: counted(0))
        end
        connection.autocommit = true
        copy = connection.copy_in("DOCS")
        copy << [big]

        assert_nil copy.abandon
        connection.terminate
        begin_copy, data, finish = server.join

        assert_equal Protocol::Requests.copy_in("DOCS", [], ends: true), Protocol::Frame.encode(*begin_copy)
        assert_equal "J".ord, data.first
        assert_equal Protocol::Requests.copy_end(abandon: true), Protocol::Frame.encode(*finish)
      end

      # Verifies: [CLIENT Copying and exporting] copy_rows copies what an
      # iterator gives; a block's copy finished as it ends, abandoned if it
      # raises or gives up; a refused row's failure from finish, every row
      # undone, its detail naming the row.
      def test_copy_rows_and_blocks
        detail = Protocol::Writer.new.u8(8).str("row 2 of the copy").to_s
        connection, = scripted do |peer, frames|
          3.times { frames << peer.frame }
          peer.complete(0, "00000", tail: counted(2))
          2.times { frames << peer.frame }
          peer.complete(0, "00000", tail: counted(0))
          3.times { frames << peer.frame }
          failure = Protocol::Writer.new.i32(-201).str("23000").str("duplicate").flag(false).flag(false).flag(false)
          peer.reply("E", failure.raw(detail))
        end

        assert_equal 2, connection.copy_rows("T", [], [[1], [2]].each)
        assert_raises(ArgumentError) { connection.copy_in("T") { raise ArgumentError, "the program's" } }
        error = assert_fails([-201, "23000"]) { connection.copy_rows("T", [], [[1], [1]]) }

        assert_equal "row 2 of the copy", error.diagnostics.detail
        refute_predicate connection, :lost?
        connection.terminate
      end

      # Verifies: [CLIENT What a connection asks for] copy_in needs copy,
      # failing before it sends anything, the connection kept.
      def test_copy_needs_its_capability
        connection, server = scripted([]) { nil }

        assert_fails { connection.copy_in("T") }
        refute_predicate connection, :lost?
        connection.terminate

        assert_equal ["X".ord], server.join.map(&:first)
      end

      # Verifies: [PROTOCOL CopyData 'J'] a row of a value the protocol
      # cannot carry refused whole, before it is sent, the copy kept and the
      # rows before and after it sent as they are.
      def test_a_row_refused_whole
        connection, server = scripted do |peer, frames|
          3.times { frames << peer.frame }
          peer.complete(0, "00000", tail: counted(2))
        end
        copy = connection.copy_in("STAFF", %w[ID NAME])
        copy << [7, "Niklaus"]

        assert_fails(DATA_EXCEPTION) { copy << [8, Object.new] }
        copy << [9, "Barbara"]

        assert_equal 2, copy.finish
        connection.terminate
        _, data, = server.join

        assert_equal Protocol::Requests.copy_data([[7, "Niklaus"], [9, "Barbara"]]), Protocol::Frame.encode(*data)
      end

      # Verifies: [PROTOCOL CopyColumns 'O'] granted columns, a run of rows
      # of as many values, each a character string or null, goes by column: rows, then each column's null bits,
      # ends and text, a null cell ending where the one before it ends, an
      # empty string a cell of no text; a row of another value, or of
      # another count of values, by row in a CopyData between, the order
      # kept; rows past a chunk in a CopyColumns of their own.
      # Verifies: [CLIENT Copying and exporting] rows copied by column, each
      # cell its value's text, where the server grants columns.
      def test_copy_by_column
        connection, server = scripted(BY_COLUMN) do |peer, frames|
          7.times { frames << peer.frame }
          peer.complete(0, "00000", tail: counted(6))
        end
        copy = connection.copy_in("T", %w[A B])
        copy << ["7", nil] << ["1.5", ""] << [nil, "é"] << [1.5, "x"] << %w[s f] << %w[1 2 3]
        copy << ["x" * Copy::CHUNK_BYTES, nil]

        assert_equal 6, copy.finish
        connection.terminate
        _, first, by_row, second, odd, big, = server.join.map { |kind, body| [kind.chr, body] }

        assert_equal Protocol::Requests.copy_columns(3, [["\x04".b, [1, 4, 4], "71.5"], ["\x01".b, [0, 0, 2], "é".b]]),
                     Protocol::Frame.encode(first.first.ord, first.last)
        assert_equal %w[J O J O], [by_row, second, odd, big].map(&:first)
        assert_equal Protocol::Requests.copy_columns(1, [["\x00".b, [1], "s"], ["\x00".b, [1], "f"]]),
                     Protocol::Frame.encode(second.first.ord, second.last)
      end
    end
  end
end
