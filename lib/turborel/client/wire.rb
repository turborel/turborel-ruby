# frozen_string_literal: true

module Turborel
  module Client
    # A connection's frames: each request sent, compressed past its
    # threshold once compression is granted, and each reply read and
    # decoded, inflated if it came compressed, each Status before a reply
    # taken on the way [PROTOCOL Requests].
    #
    # @api private
    module Wire
      # Whether +failure+ ends the connection it came on: a connection
      # exception, class 08, but 08003, which names another connection; or
      # credentials refused of a connection exception's SQLCODE, as the
      # connection is made.
      #
      # @param failure [Failure]
      # @return [Boolean]
      def self.ends_connection?(failure)
        connecting = failure.sqlcode == Error::CONNECTION_FAILURE_SQLCODE
        exception = failure.sqlstate.start_with?("08") && failure.sqlstate != "08003"
        exception || (connecting && failure.sqlstate.start_with?("28"))
      end

      private

      # Sends +frames+, requests already encoded.
      def send_frame(frames)
        lost = @lost
        raise lost if lost

        threshold = @compress_from
        frames = Protocol::Compression.compress_frames(frames, threshold) if threshold
        @stream.write_all(frames)
      rescue Error => e
        raise lost_by(e)
      end

      # The server's next reply, each Status before it taken.
      def receive
        loop do
          reply = next_reply
          return reply unless reply.is_a?(Protocol::Replies::Status)

          @settings[reply.name] = reply.value
        end
      end

      # The next frame the server sends, decoded: inflated first if it is
      # compressed and compression was granted; a z frame received without
      # the grant fails the connection [PROTOCOL Compressed frames].
      def next_reply
        lost = @lost
        raise lost if lost

        kind, length = Protocol::Frame.decode_header(@stream.read_exactly(Protocol::Frame::HEADER_BYTES), @max_body)
        body = @stream.read_exactly(length)
        kind, body = inflated(body) if kind == Protocol::Compression::COMPRESSED && @compress_from
        Protocol::Replies.decode(kind, body)
      rescue Error => e
        raise lost_by(e)
      end

      # The kind and body the z frame +body+ holds.
      def inflated(body) = Protocol::Compression.decompress(body, @max_body)

      # +failure+ as an error, the connection lost if it ends it: of class
      # 08 but 08003, or of class 28 as the connection is made [PROTOCOL
      # Error 'E'].
      def failed(failure)
        error = Error.new(failure)
        @lost = error if Wire.ends_connection?(failure)
        error
      end

      # Loses the connection, for a connection failure +message+.
      def lose(message) = lost_by(Error.connection_failure(message))

      # Loses the connection for +error+, closing its stream.
      def lost_by(error)
        @lost ||= error
        @stream.close
        error
      end
    end
  end
end
