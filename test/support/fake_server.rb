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
      def error(sqlcode, sqlstate, message, active: false)
        body = Protocol::Writer.new.i32(sqlcode).str(sqlstate).str(message).flag(false).flag(false).flag(active)
        write(Protocol::Frame.encode("E".ord, body.to_s))
      end

      # Writes a reply of +kind+, its body +body+.
      def reply(kind, body = "") = write(Protocol::Frame.encode(kind.ord, body.to_s))

      # Writes Complete of +sqlcode+ and +sqlstate+, whether a transaction
      # is +active+ after it, then +tail+, its tail's bytes.
      def complete(sqlcode = 0, sqlstate = "00000", active: false, tail: "")
        reply("K", Protocol::Writer.new.i32(sqlcode).str(sqlstate).flag(active).raw(tail))
      end

      # Writes Notice of +sqlstate+ and +message+.
      def notice(sqlstate, message = "noted") = reply("N", Protocol::Writer.new.str(sqlstate).str(message))

      # Writes Description of INTEGER columns named +names+.
      def description(*names) = reply("D", columns(names))

      # Writes Rows of +rows+, each an Array of Integers.
      def rows(*rows)
        writer = Protocol::Writer.new.u32(rows.size)
        rows.each { |row| Protocol::ValueWriter.row_values(writer, row) }
        reply("B", writer)
      end

      # Writes Prepared of statement +number+, +parameters+ INTEGER
      # parameters, and INTEGER columns named +names+.
      def prepared(number, parameters, *names)
        writer = Protocol::Writer.new.u32(number).u32(parameters)
        parameters.times { writer.flag(false).raw(INTEGER) }
        reply("P", writer.raw(columns(names)))
      end

      # The bytes of a list of INTEGER columns named +names+.
      def columns(names)
        writer = Protocol::Writer.new.u32(names.size)
        names.each { |name| writer.flag(true).str(name).raw(INTEGER).flag(false) }
        writer.to_s
      end
    end

    # The data type INTEGER: exact, precision 10, scale 0.
    INTEGER = "\x02\x0A\x00\x00\x00\x00\x00\x00\x00".b
  end
end
