# frozen_string_literal: true

require "io/wait"
require "openssl"

module Turborel
  module Client
    # A connection's stream: TCP, a Unix socket, a named pipe or TLS over
    # TCP, each read and write bounded by its +timeout+ in seconds, +nil+
    # for none [CLIENT Timeouts]. A named pipe is bounded only as it is
    # opened: its reads and writes wait as long as they must, as Ruby
    # sets no limit of time on a file's.
    #
    # @api private
    class Stream
      # The most bytes read at a time.
      CHUNK = 64 * 1024
      # What a stream fails with, of the system or of TLS, as a lost
      # connection.
      FAILURES = [SystemCallError, IOError, OpenSSL::SSL::SSLError, SocketError].freeze

      # @return [Numeric, nil] how long each read and write waits
      attr_accessor :timeout

      # @return [IO, OpenSSL::SSL::SSLSocket] what it reads and writes
      attr_reader :io

      # A stream over +io+.
      #
      # @param io [IO, OpenSSL::SSL::SSLSocket]
      # @param timeout [Numeric, nil]
      # @param bounded [Boolean] whether its waits can be bounded: not of a
      #   named pipe
      def initialize(io, timeout: nil, bounded: true)
        @io = io
        @timeout = timeout
        @bounded = bounded
        @buffer = +"".b
      end

      # Writes +bytes+ whole.
      #
      # @param bytes [String]
      # @return [void]
      # @raise [Error] a connection failure if it cannot, in time
      def write_all(bytes)
        return guarded("send") { @io.write(bytes) && @io.flush } unless @bounded

        rest = bytes.b
        guarded("send") { rest = rest.byteslice(written(rest), rest.bytesize) || "".b until rest.empty? }
        @io.flush if @io.respond_to?(:flush)
      end

      # The next +count+ bytes.
      #
      # @param count [Integer]
      # @return [String] binary
      # @raise [Error] a connection failure if the server closes first, or
      #   does not send them in time
      def read_exactly(count)
        fill(count)
        if @buffer.bytesize < count
          raise Error.connection_failure("cannot receive: the connection closed within a reply")
        end

        taken = @buffer.byteslice(0, count) || "".b
        @buffer = @buffer.byteslice(count, @buffer.bytesize) || "".b
        taken
      end

      # Whether the server has closed, nothing more to read; it waits, as
      # bounded, for a byte or the close.
      #
      # @return [Boolean]
      def at_end?
        fill(1)
        @buffer.empty?
      end

      # What the server sends until it closes, at most +limit+ bytes.
      #
      # @param limit [Integer]
      # @return [String]
      def read_to_end(limit)
        fill(limit)
        @buffer.byteslice(0, limit) || "".b
      end

      # Whether it can be bounded: not a named pipe, nor a stream given to
      # open.
      #
      # @return [Boolean]
      def bounded? = @bounded

      # Whether the server begins to send within +seconds+, without limit
      # if +nil+: what it sent buffered, nothing of it taken. A stream that
      # cannot be bounded waits without limit.
      #
      # @param seconds [Numeric, nil]
      # @return [Boolean]
      # @raise [Error] a connection failure if the server closes
      def arrives_within?(seconds)
        return true unless @buffer.empty?

        chunk = @bounded ? first_chunk(seconds) : guarded("receive") { next_chunk(CHUNK) }
        return false if chunk == :later
        raise Error.connection_failure("cannot receive: the server closed the connection") unless chunk

        @buffer << chunk
        true
      end

      # Closes it, whatever the system says.
      #
      # @return [void]
      def close
        @io.close
      rescue *FAILURES
        nil
      end

      private

      # Reads until +count+ bytes are buffered, or the server closes.
      def fill(count)
        guarded("receive") do
          while @buffer.bytesize < count
            chunk = next_chunk(count - @buffer.bytesize)
            break unless chunk

            @buffer << chunk
          end
        end
      end

      # The next bytes the server sends, at most +wanted+; +nil+ once it
      # has closed.
      def next_chunk(wanted)
        size = [wanted, CHUNK].min
        return @io.readpartial(size) unless @bounded

        loop do
          chunk = @io.read_nonblock(size, exception: false)
          return chunk unless chunk.is_a?(Symbol)

          wait(chunk)
        end
      rescue EOFError
        nil
      end

      # The first bytes the server sends within +seconds+: +:later+ if none
      # came, +nil+ once it has closed.
      def first_chunk(seconds)
        guarded("receive") do
          chunk = @io.read_nonblock(CHUNK, exception: false)
          while chunk.is_a?(Symbol)
            socket = @io.to_io
            return :later unless chunk == :wait_writable ? socket.wait_writable(seconds) : socket.wait_readable(seconds)

            chunk = @io.read_nonblock(CHUNK, exception: false)
          end
          chunk
        end
      end

      # The bytes of +bytes+ written now, waiting while none can be.
      def written(bytes)
        loop do
          count = @io.write_nonblock(bytes, exception: false)
          return count unless count.is_a?(Symbol)

          wait(count)
        end
      end

      # Waits until the stream can go on as +why+ says, as its timeout
      # allows.
      def wait(why)
        socket = @io.to_io
        ready = why == :wait_writable ? socket.wait_writable(@timeout) : socket.wait_readable(@timeout)
        raise Error.connection_failure("the server did not answer in time") unless ready
      end

      # The block's result, a failure of the system as the connection
      # lost, saying what could not be done.
      def guarded(what)
        yield
      rescue Error, *FAILURES => e
        raise Error.connection_failure("cannot #{what}: #{e.message}")
      end
    end
  end
end
