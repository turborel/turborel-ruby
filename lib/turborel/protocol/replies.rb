# frozen_string_literal: true

module Turborel
  module Protocol
    # Every reply the client receives, decoded from its frame's kind and
    # body [PROTOCOL Replies]. A kind no reply has, a body cut short, or
    # bytes left over after the last field fail the connection [PROTOCOL
    # Frames].
    #
    # @api private
    module Replies
      # The next step of an authentication exchange [PROTOCOL Challenge 'C'].
      Challenge = Data.define(:challenge)
      # The client is authenticated [PROTOCOL Ready 'R']: the session's
      # authorization identifier, the 16-byte key that cancels its
      # statements, the capabilities granted, and the server's product.
      Ready = Data.define(:authorization, :key, :capabilities, :server)
      # A statement prepared or described [PROTOCOL Prepared 'P']: its
      # number, its parameters in the order of their marks, its columns.
      Prepared = Data.define(:statement, :parameters, :columns)
      # The columns of the rows that follow [PROTOCOL Description 'D'].
      Description = Data.define(:columns)
      # A batch of rows, each an Array of values [PROTOCOL Rows 'B'].
      Rows = Data.define(:rows)
      # The rows asked for were sent and the cursor has more [PROTOCOL
      # Suspended 'S'].
      Suspended = Data.define
      # The server's time for a statement, in microseconds: total, queued
      # and waiting for locks [PROTOCOL Complete 'K'].
      Timing = Data.define(:total, :queued, :locks)
      # A statement's completion [PROTOCOL Complete 'K']: SQLCODE,
      # SQLSTATE, whether a transaction is active, and the tail's commit
      # position, more, rows, generated values, conditions (each a
      # Failure) and Timing, +nil+ or empty where not sent.
      Complete = Data.define(:sqlcode, :sqlstate, :active, :position, :more, :rows, :generated, :conditions, :time)
      # A statement's failure, or the connection's [PROTOCOL Error 'E'].
      ErrorReply = Data.define(:failure)
      # The data a Lob read asked for [PROTOCOL Replies].
      LobData = Data.define(:data)
      # The locator a Lob create made [PROTOCOL Replies].
      LobLocator = Data.define(:locator)
      # A condition a statement raised, or a notice of the server's own
      # [PROTOCOL Notice 'N'].
      Notice = Data.define(:sqlstate, :message, :diagnostics)
      # A setting of the session [PROTOCOL Status 'T']: its name, and its
      # value as SQL writes it, empty for a null.
      Status = Data.define(:name, :value)
      # The answer to Ping [PROTOCOL Pong 'G'].
      Pong = Data.define

      # The kinds of the replies, and how each body is read: the method of
      # this module [PROTOCOL Replies].
      READERS = {
        "C".ord => :challenge, "R".ord => :ready, "P".ord => :prepared, "D".ord => :description,
        "B".ord => :rows, "S".ord => :suspended, "K".ord => :complete, "E".ord => :error,
        "L".ord => :lob, "N".ord => :notice, "T".ord => :status, "G".ord => :pong
      }.freeze
      # The tags a Complete takes [PROTOCOL The tail].
      COMPLETE_TAGS = [Tail::POSITION, Tail::MORE, Tail::ROWS, Tail::GENERATED, Tail::CONDITIONS, Tail::TIME].freeze
      # The kinds of the replies a request has more replies after: a
      # Description, Rows, a Notice and a Status.
      GOING_ON = %w[D B N T].map(&:ord).freeze
      # The kind of a Complete.
      COMPLETE = "K".ord
      # A Lob reply's kinds [PROTOCOL Replies].
      LOB_DATA = 0
      # (see LOB_DATA)
      LOB_LOCATOR = 1

      # The reply of +kind+ whose body is +body+.
      #
      # @param kind [Integer] the frame's kind
      # @param body [String] the frame's body
      # @return [Data] the reply
      # @raise [Error] a connection failure if it is malformed
      def self.decode(kind, body)
        reader = Reader.new(body, "reply")
        method = READERS.fetch(kind) { raise Error.connection_failure("no reply is of kind #{kind}") }
        reply = send(method, reader)
        reader.finish
        reply
      end

      # Whether a reply of +kind+ and +body+, decoded or not, is the last
      # its request is answered with, by the order of a statement's replies,
      # as turborel-protocol's reply.rs ends_request says: a Description,
      # Rows, a Notice or a Status has more after it; a Complete has if its
      # head says more follow; any other ends its request's.
      #
      # @param kind [Integer]
      # @param body [String]
      # @return [Boolean]
      def self.ends_request?(kind, body)
        return false if GOING_ON.include?(kind)
        return true unless kind == COMPLETE

        !completed_head(kind, body)&.more
      end

      # The head of a reply of +kind+ and +body+, if a Complete whose head
      # reads: its SQLCODE, SQLSTATE and whether a transaction is active,
      # and of its tail the commit's position and whether more follow,
      # which come before anything a client may fail to take, as
      # reply.rs completed_head reads it.
      #
      # @param kind [Integer]
      # @param body [String]
      # @return [Complete, nil]
      def self.completed_head(kind, body)
        return nil unless kind == COMPLETE

        reader = Reader.new(body, "reply")
        generated = [] #: Array[String]
        conditions = [] #: Array[Failure]
        fields = { sqlcode: ValueReader.signed32(reader.u32), sqlstate: reader.str, active: reader.flag, position: nil,
                   more: false, rows: nil, generated:, conditions:, time: nil }
        head_tail(reader, fields)
        Complete.new(**fields)
      rescue Error
        nil
      end

      # Reads into +fields+ a Complete's position and whether more follow,
      # to its first other tag.
      #
      # @api private
      # @return [void]
      def self.head_tail(reader, fields)
        Tail.new(reader, COMPLETE_TAGS).each_tag do |tag|
          case tag
          when Tail::POSITION then fields[:position] = reader.u64
          when Tail::MORE then fields[:more] = true
          else break
          end
        end
      end

      # @return [Challenge] bytes
      def self.challenge(reader) = Challenge.new(challenge: reader.bytes)

      # @return [Ready] authorization, key of 16 bytes, capabilities, server
      def self.ready(reader)
        Ready.new(authorization: reader.str, key: reader.take(Requests::KEY_BYTES), capabilities: reader.strs,
                  server: reader.str)
      end

      # @return [Prepared] statement u32, a list of parameters, a list of
      #   columns
      def self.prepared(reader)
        Prepared.new(statement: reader.u32, parameters: reader.counted { Fields.parameter(reader) },
                     columns: declared(reader, reader.counted { Fields.column(reader) }))
      end

      # @return [Description] a list of columns
      def self.description(reader)
        Description.new(columns: declared(reader, reader.counted { Fields.column(reader) }))
      end

      # +columns+, each given its declared type where the tail's tag 19
      # tells them, one for each column, in order [PROTOCOL Declared types].
      #
      # @param reader [Reader]
      # @param columns [Array<Column>]
      # @return [Array<Column>]
      def self.declared(reader, columns)
        told = columns
        Tail.new(reader, [Tail::DECLARED]).each_tag do
          types = reader.counted { Declared.new(name: reader.str, written: reader.str) }
          raise reader.corrupt("its declared types are not one for each column") unless types.size == columns.size

          told = columns.zip(types).map { |column, type| column.with(declared: type) }
        end
        told
      end

      # @return [Rows] a list of rows
      def self.rows(reader) = Rows.new(rows: reader.counted { ValueReader.row_values(reader) })

      # @return [Suspended]
      def self.suspended(_reader) = Suspended.new

      # Complete: SQLCODE as u32, SQLSTATE, active flag, then tail 4, 5,
      # 6, 16, 17 and 18.
      #
      # @return [Complete]
      def self.complete(reader)
        generated = [] #: Array[String]
        conditions = [] #: Array[Failure]
        fields = { sqlcode: ValueReader.signed32(reader.u32), sqlstate: reader.str, active: reader.flag, position: nil,
                   more: false, rows: nil, generated:, conditions:, time: nil }
        Tail.new(reader, COMPLETE_TAGS).each_tag { |tag| fields.merge!(completed(reader, tag)) }
        Complete.new(**fields)
      end

      # The field of a Complete's tail tag +tag+.
      #
      # @return [Hash]
      def self.completed(reader, tag)
        case tag
        when Tail::POSITION then { position: reader.u64 }
        when Tail::MORE then { more: true }
        when Tail::ROWS then { rows: reader.u64 }
        when Tail::GENERATED then { generated: reader.strs }
        when Tail::CONDITIONS then { conditions: reader.counted { condition(reader.bytes) } }
        else { time: Timing.new(total: reader.u64, queued: reader.u64, locks: reader.u64) }
        end
      end

      # A condition of a Complete: a failure written as bytes, so its own
      # tail ends where its length does.
      #
      # @param bytes [String]
      # @return [Failure]
      def self.condition(bytes)
        reader = Reader.new(bytes, "condition")
        failure = Fields.failure(reader)
        reader.finish
        failure
      rescue Error => e
        raise Error.corrupt_value("a condition is malformed: #{e.message}")
      end

      # @return [ErrorReply] a failure
      def self.error(reader) = ErrorReply.new(failure: Fields.failure(reader))

      # @return [LobData, LobLocator] what u8, then by what
      def self.lob(reader)
        what = reader.u8
        case what
        when LOB_DATA then LobData.new(data: reader.bytes)
        when LOB_LOCATOR then LobLocator.new(locator: reader.u32)
        else raise reader.corrupt("no Lob reply is of kind #{what}")
        end
      end

      # @return [Notice] SQLSTATE, message, then tail 7 to 15
      def self.notice(reader)
        Notice.new(sqlstate: reader.str, message: reader.str, diagnostics: Fields.diagnostics(reader))
      end

      # @return [Status] name, value
      def self.status(reader) = Status.new(name: reader.str, value: reader.str)

      # @return [Pong]
      def self.pong(_reader) = Pong.new
    end
  end
end
