# frozen_string_literal: true

module Turborel
  module Client
    # A connection's copies [CLIENT Copying and exporting]: rows sent into
    # a table, many to a message and no reply each, all or nothing.
    module Copy
      # The octets of rows a CopyData carries, about, turborel-client's
      # CHUNK_BYTES: enough that a message's cost is shared by many rows,
      # few enough that neither side holds much.
      CHUNK_BYTES = 256 * 1024

      # Begins a copy into +table+, as SQL names it, of +columns+, in
      # order, all of the table's if none; under autocommit the copy is
      # its transaction's own [PROTOCOL CopyIn 'I']. With a block, gives it
      # the copy and finishes it as the block ends, abandoning it if the
      # block raises; while a copy is under way the connection sends
      # nothing else but Ping.
      #
      # @param table [String]
      # @param columns [Array<String>]
      # @yieldparam copy [Copying]
      # @return [Copying, Integer] the copy, or with a block the rows
      #   inserted, none if the block abandoned it
      # @raise [Error] a connection failure: copy not granted, or the server
      #   gone; with a block, as Copying#finish's
      def copy_in(table, columns = [])
        copy = copy_begin(table, columns, @autocommit)
        return copy unless block_given?

        begin
          yield copy
        rescue StandardError
          copy.abandon unless copy.ended? || lost?
          raise
        end
        copy.ended? ? 0 : copy.finish
      end

      # Copies +rows+, each an Array of values, into +table+'s +columns+.
      #
      # @param table [String]
      # @param columns [Array<String>]
      # @param rows [Enumerable<Array>]
      # @return [Integer] the rows inserted
      # @raise [Error] as copy_in's and Copying#finish's
      def copy_rows(table, columns, rows)
        copy_in(table, columns) { |copy| rows.each { |row| copy << row } }
      end

      # Begins a copy into +table+'s +columns+, the transaction ended with
      # it if +ends+.
      #
      # @api private
      # @return [Copying]
      def copy_begin(table, columns, ends)
        needs(false, Protocol::Capabilities::COPY)
        send_frame(Protocol::Requests.copy_in(table, columns, ends:))
        @copying = Copying.new(_ = self)
      end

      # Ends the copy under way, abandoned if +abandon+: the rows inserted.
      #
      # @api private
      # @return [Integer]
      def copy_end(abandon)
        send_frame(Protocol::Requests.copy_end(abandon:))
        @copying = nil
        completion_reply.rows || 0
      ensure
        @copying = nil
      end

      # Sends +encoded+, rows already written, +count+ of them, as one
      # CopyData.
      #
      # @api private
      # @return [void]
      def copy_data(count, encoded)
        send_frame(Protocol::Frame.encode(Protocol::Requests::COPY_DATA,
                                          Protocol::Writer.new.u32(count).raw(encoded).to_s))
      end
    end

    # A copy under way, over its connection [CLIENT Copying and exporting]:
    # rows sent many to a CopyData once they are about CHUNK_BYTES, then
    # finished or abandoned.
    class Copying
      # A copy over +connection+.
      #
      # @api private
      def initialize(connection)
        @connection = connection
        @waiting = Protocol::Writer.new
        @count = 0
        @ended = false
      end

      # Sends +row+, an Array of a value for each column, with those before
      # it once they are about CHUNK_BYTES. A row the server refuses comes
      # as finish's failure.
      #
      # @param row [Array]
      # @return [Copying] itself
      # @raise [Error] a value the protocol cannot carry; a connection
      #   failure
      def <<(row)
        raise Error.misused("the copy has ended") if @ended

        Protocol::ValueWriter.row_values(@waiting, row)
        @count += 1
        flush if @waiting.size >= Copy::CHUNK_BYTES
        self
      end

      # Ends the copy: the rows inserted [PROTOCOL CopyEnd 'N'].
      #
      # @return [Integer]
      # @raise [Error] the copy's failure, every row of it undone: the
      #   table or a column not found, a row of too many or too few values,
      #   a value its column refuses, its detail naming the row; a
      #   connection failure
      def finish
        raise Error.misused("the copy has ended") if @ended

        flush
        ended(false)
      end

      # Gives the copy up: every row of it undone.
      #
      # @return [void]
      # @raise [Error] a connection failure
      def abandon
        raise Error.misused("the copy has ended") if @ended

        ended(true)
        nil
      end

      # @return [Boolean] whether it was finished or abandoned
      def ended? = @ended

      private

      # Sends the rows waiting.
      def flush
        return if @count.zero?

        @connection.copy_data(@count, @waiting.to_s)
        @waiting = Protocol::Writer.new
        @count = 0
      end

      # Sends CopyEnd: the rows inserted.
      def ended(abandon)
        @ended = true
        @connection.copy_end(abandon)
      end
    end
  end
end
