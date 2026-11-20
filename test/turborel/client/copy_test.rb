# frozen_string_literal: true

require "stringio"
require "test_helper"
require_relative "../../support/fake_server"

module Turborel
  module Client
    # Copies and exports, against a server of the test's own script.
    class CopyTest < Minitest::Test
      include TestSupport

      # Every capability but compression, so frames come as they are.
      GRANTED = Protocol::Capabilities::ALL - [Protocol::Capabilities::COMPRESSION]

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
      # CopyData, CopyEnd and Ping sent, anything else refused before it is
      # sent (TB910).
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
    end
  end
end
