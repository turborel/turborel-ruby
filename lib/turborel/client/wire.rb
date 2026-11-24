# frozen_string_literal: true

module Turborel
  module Client
    # A connection's frames: each request sent, compressed past its
    # threshold once compression is granted, and each reply read and
    # decoded, inflated if it came compressed, each Notice and Status before
    # a statement's reply taken on the way, each debugger's Event kept,
    # and what each reply says of the session noted [PROTOCOL Requests].
    #
    # @api private
    module Wire
      # The most notices kept for a connection with no handler: the oldest
      # dropped past them, turborel-client's KEPT_NOTICES.
      KEPT_NOTICES = 64
      # The SQLSTATE class of a completion condition, a warning.
      WARNING_CLASS = "01"
      # The requests sent while a copy is under way.
      WHILE_COPYING = [Protocol::Requests::COPY_DATA, Protocol::Requests::COPY_END, Protocol::Requests::PING].freeze

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

        copying!(frames)
        written(frames)
      end

      # Writes +frames+, compressed past the threshold once granted; a
      # failure loses the connection.
      def written(frames)
        threshold = @compress_from
        frames = Protocol::Compression.compress_frames(frames, threshold) if threshold
        @stream.write_all(frames)
      rescue Error => e
        raise lost_by(e)
      end

      # Refuses +frames+ while a copy is under way unless they are CopyData,
      # CopyEnd or Ping [PROTOCOL CopyIn 'I'].
      def copying!(frames)
        return unless @copying && !WHILE_COPYING.include?(frames.getbyte(0))

        raise Error.misused("a copy is under way: finish or abandon it first")
      end

      # The next reply, of one of +kinds+; an Error its failure raised; any
      # other loses the connection. +answer+ says how the request is
      # answered: by :replies, a statement's, or by :one, as a Describe of
      # a cursor is by a Description no rows follow.
      def expect(*kinds, answer: :replies)
        reply = receive(answer)
        raise failed(reply.failure) if reply.is_a?(Protocol::Replies::ErrorReply)
        unless kinds.include?(reply.class)
          raise lose("the server sent #{reply.class.name.to_s.split("::").last} out of turn")
        end

        reply
      end

      # The server's Completion.
      def completion_reply = expect(Protocol::Replies::Complete)

      # One statement's outcome, Rows or a Completion, and whether another
      # statement's replies follow; a query's rows broken off by Suspended
      # lose the connection, as a direct query has no cursor to suspend.
      def outcome
        first = expect(Protocol::Replies::Complete, Protocol::Replies::Description)
        return [first, first.more] if first.is_a?(Protocol::Replies::Complete)

        rows, ended = rows_until_end
        raise lose("the server broke off its rows") unless ended

        [Rows.new(columns: first.columns, rows:), ended.more]
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

      # The server's next reply, each Notice and Status before it taken; a
      # reply with a value the driver cannot take read past with the rest
      # of its request's, as +answer+ says they are told.
      def receive(answer = :replies)
        loop do
          reply = took(next_reply(answer))
          return reply if reply
        end
      end

      # +reply+, unless a Notice, a Status or a debugger's Event, which is
      # taken, the Event kept for debug_wait; a reply of a statement, what
      # it says noted.
      def took(reply)
        case reply
        when Protocol::Replies::Notice then notice(reply)
        when Protocol::Replies::Status then @settings[reply.name] = reply.value
        when Debug::Event then events_kept << reply
        else return noted(reply)
        end
        nil
      end

      # The debugger's Events kept, not yet waited for.
      def events_kept = @events_kept ||= []

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

      # The next frame the server sends, decoded. A frame read whole that
      # does not decode is malformed, which loses the connection (08006),
      # or holds a value the driver cannot take, which fails its request
      # alone (SQLCODE -916, or -900 past a limit) once the rest of its
      # replies are read past, under :replies, so the next request takes
      # its own [PROTOCOL Values and fields].
      def next_reply(answer = :replies)
        kind, body = next_frame
        begin
          Protocol::Replies.decode(kind, body)
        rescue Error => e
          skipped(kind, body, e)
          drained(kind, body) if answer == :replies
          raise e
        end
      end

      # The next frame the server sends, its kind and body: inflated first
      # if it is compressed and compression was granted; a z frame received
      # without the grant fails the connection [PROTOCOL Compressed
      # frames]. One not whole, or whose header or compression is
      # malformed, loses the connection.
      def next_frame
        lost = @lost
        raise lost if lost

        kind, length = Protocol::Frame.decode_header(@stream.read_exactly(Protocol::Frame::HEADER_BYTES), @max_body)
        body = @stream.read_exactly(length)
        kind == Protocol::Compression::COMPRESSED && @compress_from ? inflated(body) : [kind, body]
      rescue Error => e
        raise lost_by(e)
      end

      # Takes a frame of +kind+ and +body+ that did not decode, for +error+:
      # the connection lost if it ends it, as a malformed frame's does; else
      # of a Complete, what its head says noted as its whole would be.
      def skipped(kind, body, error)
        raise lost_by(error) if Wire.ends_connection?(error.failure)

        head = Protocol::Replies.completed_head(kind, body)
        noted(head) if head
      end

      # Reads past the rest of a request's replies once one, of +kind+ and
      # +body+, held a value the driver cannot take: to the one that ends
      # them, each taken as receive takes it, or passed over as that one
      # was [PROTOCOL Values and fields].
      def drained(kind, body)
        until Protocol::Replies.ends_request?(kind, body)
          kind, body = next_frame
          begin
            took(Protocol::Replies.decode(kind, body))
          rescue Error => e
            skipped(kind, body, e)
          end
        end
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
