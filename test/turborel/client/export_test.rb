# frozen_string_literal: true

require "stringio"
require "test_helper"
require_relative "../../support/fake_server"

module Turborel
  module Client
    # Exports, against a server of the test's own script.
    class ExportTest < Minitest::Test
      include TestSupport

      # Runs +script+ after login, then reads Terminate.
      def scripted(&)
        server = FakeServer.new do |peer|
          peer.frame
          peer.ready(Protocol::Capabilities::ALL - [Protocol::Capabilities::COMPRESSION])
          yield(peer)
          peer.frame
        end
        [Client.connect_to(server.target, user: "ann", mechanism: Trust.new), server]
      end

      # A query of a column N and a text T answered with +rows+.
      def answered(peer, rows)
        peer.frame
        columns = Protocol::Writer.new.u32(2)
        columns.flag(true).str("N").raw(FakeServer::INTEGER).flag(false)
        columns.flag(true).str("T, quoted").raw("\x05\x14\x00\x00\x00\x00".b).flag(false)
        peer.reply("D", columns)
        peer.rows(*rows)
        peer.complete
      end

      # Verifies: [CLIENT Copying and exporting] an export as CSV: a header
      # of the columns' names, then a record for each row, each ended by CR
      # LF, a field quoted where it holds a comma, a quote, a line break or
      # space at either end, or is empty; a null an empty field.
      def test_csv
        connection, server = scripted { |peer| answered(peer, [[1, "a,b"], [nil, ""], [3, " x"], [4, "say \"hi\""]]) }
        out = StringIO.new

        assert_equal 4, connection.export("SELECT N, T FROM X", out)
        assert_equal "N,\"T, quoted\"\r\n1,\"a,b\"\r\n,\"\"\r\n3,\" x\"\r\n4,\"say \"\"hi\"\"\"\r\n", out.string
        connection.terminate
        server.join
      end

      # Verifies: [CLIENT Copying and exporting] an export as the protocol's
      # own frames, read back with every value as it was; input that is not
      # native rows refused.
      def test_native
        connection, server = scripted { |peer| answered(peer, [[1, "a"], [2, nil]]) }
        out = StringIO.new
        connection.export("SELECT N, T FROM X", out, :native)
        columns, rows = Export.read_native(StringIO.new(out.string))

        assert_equal [["N", "T, quoted"], [[1, "a"], [2, nil]]], [columns.map(&:name), rows]
        assert_fails { Export.read_native(out.string.byteslice(0, 3)) }
        assert_fails { Export.read_native(out.string.byteslice(0, out.string.bytesize - 1)) }
        assert_fails { Export.read_native(Protocol::Frame.encode("K".ord, "")) }
        description = out.string.byteslice(0, out.string.index("B".b, 5))
        assert_fails { Export.read_native(description + Protocol::Frame.encode("G".ord, "")) }
        assert_fails(MISUSED) { connection.export("VALUES 1", out, :json) }
        connection.terminate
        server.join
      end

      # Verifies: [CLIENT Copying and exporting] an export runs a query: a
      # statement that is no query fails; a write that fails ends it.
      def test_no_query_and_a_failing_write
        connection, server = scripted do |peer|
          peer.frame
          peer.complete
          answered(peer, [[1, "a"]])
        end

        assert_fails { connection.export("COMMIT", StringIO.new) }
        broken = Object.new
        broken.define_singleton_method(:write) { |bytes| bytes.start_with?("1,") ? raise(IOError, "full") : bytes.size }
        assert_fails { connection.export("SELECT N, T FROM X", broken) }
        connection.terminate
        server.join
      end
    end
  end
end
