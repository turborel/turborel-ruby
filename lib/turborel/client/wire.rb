# frozen_string_literal: true

module Turborel
  module Client
    # A connection's frames: each request sent, compressed past its
    # threshold once compression is granted, and each reply read and
    # decoded, inflated if it came compressed, each Notice and Status before
    # a statement's reply taken on the way, and what each reply says of the
    # session noted [PROTOCOL Requests].
    #
    # @api private
    module Wire
      # The most notices kept for a connection with no handler: the oldest
      # dropped past them, turborel-client's KEPT_NOTICES.
      KEPT_NOTICES = 64
      # The SQLSTATE class of a completion condition, a warning.
      WARNING_CLASS = "01"

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

      # The next reply, of one of +kinds+; an Error its failure raised; any
      # other loses the connection.
      def expect(*kinds)
        reply = receive
        raise failed(reply.failure) if reply.is_a?(Protocol::Replies::ErrorReply)
        unless kinds.include?(reply.class)
          raise lose("the server sent #{reply.class.name&.split("::")&.last} out of turn")
        end

        reply
      end

      # The server's Completion.
      def completion_reply = expect(Protocol::Replies::Complete)

      # One statement's outcome, Rows or a Completion, and whether another
      # statement's replies follow.
      def outcome
        first = expect(Protocol::Replies::Complete, Protocol::Replies::Description)
        return [first, first.more] if first.is_a?(Protocol::Replies::Complete)

        rows, ended = rows_until_end
        [Rows.new(columns: first.columns, rows:), ended&.more || false]
      end

      # The rows the server sends until it says whether the cursor has
      # more: the rows, and the Complete that ended them, +nil+ if
      # Suspended.
      def rows_until_end
        rows = [] #: Array[Array[value]]
        loop do
          reply = expect(Protocol::Replies::Rows, Protocol::Replies::Complete, Protocol::Replies::Suspended)
          unless reply.is_a?(Protocol::Replies::Rows)
            return [rows, reply.is_a?(Protocol::Replies::Complete) ? reply : nil]
          end

          rows.concat(reply.rows)
        end
      end

      # A connection failure, unless +allowed+ or the server granted +name+.
      def needs(allowed, name)
        return if allowed || @granted.include?(name)

        raise Error.connection_failure("the server did not grant #{name}")
      end

      # The attributes a Query or an Execute carries: none unless granted.
      def carried_attributes
        @granted.include?(Protocol::Capabilities::QUERY_ATTRIBUTES) ? @query_attributes : Protocol::Requests::NO_ATTRIBUTES
      end

      # The server's next reply, each Notice and Status before it taken.
      def receive
        loop do
          reply = next_reply
          case reply
          when Protocol::Replies::Notice then notice(reply)
          when Protocol::Replies::Status then @settings[reply.name] = reply.value
          else return noted(reply)
          end
        end
      end

      # Takes +notice+: to the handler, or kept, the last KEPT_NOTICES.
      def notice(notice)
        handler = @notice_handler
        return handler.call(notice) if handler

        @notices.shift if @notices.size >= KEPT_NOTICES
        @notices << notice
      end

      # +reply+, what it says of the session noted: whether a transaction
      # is active after it, a statement's completion and its warning, the
      # last commit's position; a query's rows and a locator are read in a
      # transaction; Ready ends a login or a change of user, which renews
      # the session as reset does, its transaction rolled back.
      def noted(reply)
        case reply
        when Protocol::Replies::Complete then completed(reply)
        when Protocol::Replies::Ready then @active = false
                                           @warning = nil
        when Protocol::Replies::ErrorReply then @active = reply.failure.active
                                                @warning = nil
        when Protocol::Replies::Description then @active = true
                                                 @warning = nil
        when Protocol::Replies::Rows, Protocol::Replies::Suspended, Protocol::Replies::LobData,
             Protocol::Replies::LobLocator then @active = true
        end
        reply
      end

      # Notes the completion +complete+.
      def completed(complete)
        @active = complete.active
        @warning = complete.sqlstate.start_with?(WARNING_CLASS) ? complete.sqlstate : nil
        @commit_position = complete.position || @commit_position
        @completion = complete
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
