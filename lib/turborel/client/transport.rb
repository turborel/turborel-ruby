# frozen_string_literal: true

require "io/wait"
require "openssl"
require "socket"

module Turborel
  module Client
    # Streams to a server, of each kind of Target [CLIENT Connecting], made
    # within the connect timeout.
    #
    # @api private
    module Transport
      # How long a client waits before it tries a busy named pipe again,
      # about as long as a server takes to make its next instance, as
      # turborel-client's BUSY_RETRY.
      BUSY_RETRY = 0.01
      # What opening a named pipe all of whose instances serve a client
      # fails with.
      BUSY = [Errno::EBUSY, Errno::EAGAIN].freeze

      # A stream to the server at +target+, and over TLS what its handshake
      # gives a mechanism to bind to.
      #
      # @param target [Target]
      # @param within [Numeric, nil] how long to wait to connect
      # @return [Array(Stream, TlsChannel)] the stream, and its channel or
      #   +nil+
      # @raise [Error] a connection failure if it cannot be reached, in
      #   time, or TLS's handshake fails
      def self.open(target, within)
        case target.kind
        when :tcp then [Stream.new(tcp(target.host.to_s, target.port || DEFAULT_PORT, within), timeout: within), nil]
        when :local then [local(target.path.to_s, within), nil]
        else tls(target, within)
        end
      end

      # A TCP connection to +host+ and +port+, each of its addresses tried
      # in turn, within +within+.
      #
      # @return [Socket]
      def self.tcp(host, port, within)
        socket = within ? Socket.tcp(host, port, connect_timeout: within) : Socket.tcp(host, port)
        socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
        socket
      rescue *Stream::FAILURES => e
        raise Error.connection_failure("cannot connect: #{e.message}")
      end

      # A stream to the local socket +path+: a Unix socket, or on Windows a
      # named pipe, tried again while it is busy, within +within+.
      #
      # @return [Stream]
      def self.local(path, within)
        return Stream.new(pipe(path, within), bounded: false) if Gem.win_platform?

        Stream.new(UNIXSocket.new(path), timeout: within)
      rescue *Stream::FAILURES => e
        raise Error.connection_failure("cannot connect: #{e.message}")
      end

      # The named pipe +path+, opened to read and write.
      #
      # @return [File]
      def self.pipe(path, within)
        began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        begin
          File.open(path, "r+b")
        rescue *BUSY
          raise Error.connection_failure("cannot connect: every instance of the pipe is busy") if past?(began, within)

          sleep(BUSY_RETRY)
          retry
        end
      end

      # @return [Boolean] whether +within+ has passed since +began+
      def self.past?(began, within) = within ? Process.clock_gettime(Process::CLOCK_MONOTONIC) - began >= within : false

      # A TLS stream to +target+, its handshake done within +within+, and
      # its channel.
      #
      # @return [Array(Stream, TlsChannel)]
      def self.tls(target, within)
        ssl = OpenSSL::SSL::SSLSocket.new(tcp(target.host.to_s, target.port || DEFAULT_PORT, within), target.context)
        ssl.sync_close = true
        ssl.hostname = target.server_name.to_s
        handshake(ssl, within)
        [Stream.new(ssl, timeout: within), TLS.channel(ssl)]
      end

      # Does +ssl+'s handshake, within +within+.
      #
      # @return [void]
      # @raise [Error] a connection failure if it fails, or takes too long
      def self.handshake(ssl, within)
        loop do
          state = ssl.connect_nonblock(exception: false)
          break if state == ssl

          socket = ssl.to_io
          ready = state == :wait_writable ? socket.wait_writable(within) : socket.wait_readable(within)
          raise Error.connection_failure("the TLS handshake did not end in time") unless ready
        end
      rescue Error
        ssl.close
        raise
      rescue *Stream::FAILURES => e
        ssl.close
        raise Error.connection_failure("the TLS handshake failed: #{e.message}")
      end
    end
  end
end
