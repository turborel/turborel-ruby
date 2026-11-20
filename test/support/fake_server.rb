# frozen_string_literal: true

require "socket"

module Turborel
  # A server of a test's own script on loopback (RULES.md R-TEST-5): it
  # takes one connection and runs the script with it, reading the client's
  # frames and writing the bytes the test chooses, so a test controls each
  # reply a connection meets.
  class FakeServer
    # The bytes of a frame's header.
    HEADER = 5

    # @return [Integer] the port it listens on
    attr_reader :port

    # A server running +script+ with the connection it takes.
    #
    # @yieldparam peer [FakeServer::Peer]
    def initialize(&)
      @listener = TCPServer.new("127.0.0.1", 0)
      @port = @listener.addr[1]
      @thread = Thread.new do
        Thread.current.report_on_exception = false
        socket = @listener.accept
        yield(Peer.new(socket))
      ensure
        socket&.close
        @listener.close
      end
    end

    # @return [Client::Target] where it is
    def target = Client::Targets.tcp("127.0.0.1", @port)

    # Waits for the script to end, giving what it gave.
    def join = @thread.value

    # A connection the server took.
    class Peer
      # @param socket [TCPSocket]
      def initialize(socket)
        @socket = socket
      end

      # @return [Array(Integer, String)] the next frame's kind and body
      def frame
        kind, length = (@socket.read(HEADER) || "").unpack("CV")
        [kind, @socket.read(length) || ""]
      end

      # Writes +bytes+.
      def write(bytes) = @socket.write(bytes)

      # @return [String] what the client sends until it closes, or resets
      def rest
        @socket.read || ""
      rescue Errno::ECONNRESET
        ""
      end

      # Writes a Ready of +capabilities+, the key sixteen 7s.
      def ready(capabilities = [], authorization: "ANN")
        body = Protocol::Writer.new.str(authorization).raw("\x07" * 16).strs(capabilities).str("turborel 0.0.0 (alpha)")
        write(Protocol::Frame.encode("R".ord, body.to_s))
      end

      # Writes a Status of +name+ and +value+.
      def status(name, value) = write(Protocol::Frame.encode("T".ord, Protocol::Writer.new.str(name).str(value).to_s))

      # Writes an Error of +sqlcode+, +sqlstate+ and +message+.
      def error(sqlcode, sqlstate, message)
        body = Protocol::Writer.new.i32(sqlcode).str(sqlstate).str(message).flag(false).flag(false).flag(false)
        write(Protocol::Frame.encode("E".ord, body.to_s))
      end
    end
  end
end
