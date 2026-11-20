# frozen_string_literal: true

require "socket"
require "test_helper"

module Turborel
  module Client
    # A connection's stream.
    class StreamTest < Minitest::Test
      include TestSupport

      def pair
        listener = TCPServer.new("127.0.0.1", 0)
        client = TCPSocket.new("127.0.0.1", listener.addr[1])
        [client, listener.accept].tap { listener.close }
      end

      # Verifies: [CLIENT Timeouts] a stream reads and writes whole, each
      # read bounded by its timeout; a wait that runs out loses the
      # connection, saying the server did not answer in time.
      def test_reads_writes_and_times_out
        client, server = pair
        stream = Stream.new(client, timeout: 0.05)
        stream.write_all("abc" * 30_000)

        assert_equal "abc" * 30_000, server.read(90_000)
        server.write("xy")

        assert_equal "x", stream.read_exactly(1)
        assert_equal "y", stream.read_exactly(1)
        error = assert_fails { stream.read_exactly(1) }

        assert_match(/did not answer in time/, error.message)
      ensure
        [client, server].each { |io| io&.close }
      end

      # Verifies: [PROTOCOL Frames] a body cut short, the connection closed
      # within a reply, fails the connection; what remains until the close
      # is read to its end.
      def test_closed_within_a_reply
        client, server = pair
        server.write("ab")
        server.close
        stream = Stream.new(client)

        assert_fails { stream.read_exactly(3) }
        assert_equal "", Stream.new(client).read_to_end(10)
        stream.close
        stream.close
        assert_fails { stream.write_all("x") }
      ensure
        client&.close
      end

      # Verifies: [CLIENT Timeouts] a named pipe is bounded only as it is
      # opened: its stream reads and writes as long as they must.
      def test_unbounded_streams
        reader, writer = IO.pipe
        stream = Stream.new(writer, bounded: false)
        stream.write_all("pipe")

        assert_equal "pipe", Stream.new(reader, bounded: false).read_exactly(4)
      ensure
        [reader, writer].each { |io| io&.close }
      end

      # Verifies: [CLIENT Timeouts] a write that waits past the timeout, as to
      # a server that reads nothing, loses the connection.
      def test_writes_time_out
        client, server = pair
        stream = Stream.new(client, timeout: 0.05)

        assert_fails { stream.write_all("x" * (64 * 1024 * 1024)) }
      ensure
        [client, server].each { |io| io&.close }
      end

      # Verifies: [CLIENT Timeouts] an unbounded stream reads to the end of
      # what is sent; closing a stream whose system refuses the close is
      # quiet.
      def test_unbounded_end_and_quiet_close
        reader, writer = IO.pipe
        writer.write("ab")
        writer.close

        assert_equal "ab", Stream.new(reader, bounded: false).read_to_end(10)
        refusing = Object.new.tap { |io| io.define_singleton_method(:close) { raise IOError, "refused" } }

        assert_nil Stream.new(refusing).close
      ensure
        reader&.close
      end
    end
  end
end
