# frozen_string_literal: true

module Turborel
  module Client
    # A connection to a server, its session's [CLIENT Connecting]: logged
    # in as Hello, Challenge and Answer say [PROTOCOL Opening a
    # connection], then one request at a time. It speaks the protocol over
    # any stream; every failure is a Turborel::Error, the server's own or
    # one of the connection, after which the connection takes no more.
    class Connection
      include Wire

      # @return [String] the session's authorization identifier, as Ready
      #   told it
      attr_reader :authorization

      # @return [String] the server's product, as "turborel 0.0.0 (alpha)"
      attr_reader :server

      # @return [Array<String>] the capabilities the server granted, in
      #   the table's order
      attr_reader :granted

      # @return [Target, nil] where it reached its server, +nil+ over a
      #   stream given to open
      attr_reader :target

      # @return [Integer] the longest reply body taken, 16 MiB unless told
      attr_accessor :max_body

      # Opens a connection over +io+, any stream that reads and writes, as
      # +user+, proved by +mechanism+, asking for what +offer+ asks. Of a
      # stream given, the caller answers for whether it keeps a secret
      # mechanism's bytes private.
      #
      # @param io [IO, OpenSSL::SSL::SSLSocket]
      # @param user [String]
      # @param mechanism [Mechanism]
      # @param offer [Offer]
      # @return [Connection]
      # @raise [Error] the server's refusal: SQLSTATE 28000 for credentials
      #   refused, 08004 for a connection refused; a connection failure
      def self.open(io, user:, mechanism:, offer: Offers.default)
        new(Stream.new(io), nil).tap { |connection| connection.log_in(user, mechanism, offer) }
      end

      # A connection over +stream+, not yet logged in.
      #
      # @param stream [Stream]
      # @param target [Target, nil]
      # @param timeouts [Timeouts, nil]
      # @api private
      def initialize(stream, target, timeouts = nil)
        @stream = stream
        @target = target
        @timeouts = timeouts
        @max_body = Protocol::Frame::MAX_BODY
        @granted = []
        @settings = {}
        @lost = nil
      end

      # Logs in by Hello, then each challenge answered until Ready.
      #
      # @return [void]
      # @api private
      def log_in(user, mechanism, offer)
        send_frame(Protocol::Requests.hello(user:, mechanism: mechanism.name, initial: mechanism.initial,
                                            capabilities: offer.capabilities, attributes: offer.attributes))
        loop do
          reply = receive
          return ready(reply, mechanism, offer) if reply.is_a?(Protocol::Replies::Ready)

          challenged(reply, mechanism)
        end
      end

      # How long each read or write of the server waits from now on, in
      # seconds; +nil+, no limit [CLIENT Timeouts].
      #
      # @param seconds [Numeric, nil]
      # @return [void]
      # @raise [Error] a connection failure over a stream given to open,
      #   which its maker bounds
      def read_timeout=(seconds)
        timeouts = @timeouts
        raise Error.connection_failure("a stream given to open is bounded by its maker") unless timeouts

        @stream.timeout = seconds
        @timeouts = timeouts.with(read: seconds)
      end

      # @return [Numeric, nil] how long each read or write waits
      def read_timeout = @timeouts&.read

      # @return [Boolean] whether the server granted the capability +name+
      def granted?(name) = @granted.include?(name)

      # @return [String, nil] the session's setting +name+ as the server
      #   last told it, with no round trip [CLIENT What the server tells]
      def setting(name) = @settings[name]

      # @return [Hash{String => String}] every setting the server told
      def settings = @settings.dup

      # @return [Boolean] whether the connection is lost: it takes no more
      def lost? = !@lost.nil?

      # What cancels the statement this connection runs, from another
      # thread: +nil+ over a stream given to open, whose server it cannot
      # reach again.
      #
      # @return [Canceller, nil]
      def canceller
        target = @target
        key = @key
        Canceller.new(target, key) if target && key
      end

      # Ends the session, its transaction as SESSION.COMMIT_AT_END says,
      # waiting for the server to close at most as the read timeout says,
      # else 60 seconds [CLIENT Connecting].
      #
      # @return [void]
      # @raise [Error] the server's, if a commit as the session ends fails;
      #   a connection failure if it does not close in time
      def terminate
        send_frame(Protocol::Requests.terminate)
        timeouts = @timeouts
        @stream.timeout = timeouts.read || TERMINATE_WITHIN if timeouts
        rest = @stream.read_to_end(@max_body + Protocol::Frame::HEADER_BYTES)
        @stream.close
        @lost = Error.connection_failure("the connection was terminated")
        terminated(rest)
      end

      # Where it reached, as whom, and whether it is lost: never its
      # cancel key.
      #
      # @return [String]
      def inspect = "#<#{self.class.name} #{@authorization.inspect} lost=#{lost?}>"

      private

      # Answers a challenge, or gives the server's refusal.
      def challenged(reply, mechanism)
        case reply
        when Protocol::Replies::Challenge then send_frame(Protocol::Requests.answer(mechanism.answer(reply.challenge)))
        when Protocol::Replies::ErrorReply
          mechanism.refused
          raise failed(reply.failure)
        else raise lose("the server sent no Ready")
        end
      end

      # Takes Ready: the session's authorization, cancel key, capabilities
      # and server; compressing requests from then on if granted.
      def ready(reply, mechanism, offer)
        mechanism.ready!
        @authorization = reply.authorization
        @server = reply.server
        @key = reply.key
        @granted = Protocol::Capabilities.known(reply.capabilities)
        @compress_from = offer.compress_from if granted?(Protocol::Capabilities::COMPRESSION)
        timeouts = @timeouts
        @stream.timeout = timeouts.read if timeouts
      end

      # The end of a terminated session: nothing, a notice or a status
      # before the close, or the failing commit's Error.
      def terminated(rest)
        return if rest.bytesize < Protocol::Frame::HEADER_BYTES

        kind, length = Protocol::Frame.decode_header(rest.byteslice(0, Protocol::Frame::HEADER_BYTES) || "", @max_body)
        body = rest.byteslice(Protocol::Frame::HEADER_BYTES, length) || ""
        kind, body = inflated(body) if kind == Protocol::Compression::COMPRESSED && @compress_from
        reply = Protocol::Replies.decode(kind, body)
        raise Error, reply.failure if reply.is_a?(Protocol::Replies::ErrorReply)
      end
    end
  end
end
