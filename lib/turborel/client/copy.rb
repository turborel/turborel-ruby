# frozen_string_literal: true

module Turborel
  module Client
    # A connection's copies [CLIENT Copying and exporting]: rows sent into
    # a table, many to a message and no reply each, all or nothing; rows
    # of character strings and nulls by column where the server grants
    # columns.
    module Copy
      # The octets of rows a CopyData carries, about, turborel-client's
      # CHUNK_BYTES: enough that a message's cost is shared by many rows,
      # few enough that neither side holds much.
      CHUNK_BYTES = 256 * 1024

      # The text of each of +row+'s values, as a cell of CopyColumns carries
      # it, +nil+ for a null; or +nil+ if a value is no character string nor
      # null. The server takes a cell as it takes the character string
      # CopyData carries, so a row goes by column only where each value is
      # one, and is taken as it would be by row [PROTOCOL CopyColumns 'O'].
      #
      # @param row [Array]
      # @return [Array<String, nil>, nil]
      def self.cells(row)
        row.map do |value|
          return nil unless value.nil? || (value.is_a?(String) && value.encoding != Encoding::BINARY)

          value && Protocol::Writer.utf8(value)
        end
      end

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

      # Sends +lanes+, rows by column, as one CopyColumns.
      #
      # @api private
      # @return [void]
      def copy_columns(lanes)
        needs(false, Protocol::Capabilities::COLUMNS)
        send_frame(Protocol::Requests.copy_columns(lanes.rows, lanes.columns))
      end
    end

    # Rows of a copy by column, as CopyColumns carries them [PROTOCOL
    # CopyColumns 'O']: of each column, a null bit for each row, where each
    # row's cell ends in its text, and its text.
    #
    # @api private
    class Lanes
      # @return [Integer] the rows held
      attr_reader :rows

      # @return [Integer] about the octets held
      attr_reader :size

      # Lanes of +width+ columns, no row yet.
      #
      # @param width [Integer]
      def initialize(width)
        @rows = 0
        @size = 0
        @nulls = Array.new(width) { +"".b }
        @ends = Array.new(width) { [] } #: Array[Array[Integer]]
        @texts = Array.new(width) { +"".b }
      end

      # @return [Integer] the columns
      def width = @texts.size

      # Adds a row of +cells+, one for each column, +nil+ for a null.
      #
      # @param cells [Array<String, nil>]
      # @return [void]
      def <<(cells)
        cells.each_with_index { |cell, i| add(i, cell) }
        @rows += 1
      end

      # @return [Array<Array(String, Array<Integer>, String)>] each column's
      #   null bits, ends and text
      def columns = @nulls.zip(@ends, @texts).map { |nulls, ends, text| [nulls, ends || [], text || "".b] }

      private

      # Adds +cell+ to column +index+ as the next row's: its text, or its
      # null bit set.
      def add(index, cell)
        text = @texts.fetch(index)
        null(@nulls.fetch(index), cell.nil?)
        text << cell.b if cell
        @ends.fetch(index) << text.bytesize
        @size += (cell&.bytesize || 0) + 4
      end

      # Adds the next row's bit to +nulls+, set if +null+.
      def null(nulls, null)
        byte, bit = @rows.divmod(8)
        nulls << "\x00".b if bit.zero?
        nulls.setbyte(byte, (nulls.getbyte(byte) || 0) | (1 << bit)) if null
      end
    end

    # A copy under way, over its connection [CLIENT Copying and exporting]:
    # rows sent many to a message once they are about CHUNK_BYTES, then
    # finished or abandoned. Where the server grants columns, a run of
    # rows each of as many values, each a character string or null, goes
    # by column in a CopyColumns; any other row by row in a CopyData, the
    # order of the rows kept.
    class Copying
      # A copy over +connection+.
      #
      # @api private
      def initialize(connection)
        @connection = connection
        @waiting = Protocol::Writer.new
        @count = 0
        @ended = false
        @by_column = connection.granted?(Protocol::Capabilities::COLUMNS)
        @lanes = nil
      end

      # Sends +row+, an Array of a value for each column, with those before
      # it once they are about CHUNK_BYTES; a row of a value the protocol
      # cannot carry is refused whole, the copy kept. A row the server
      # refuses comes as finish's failure.
      #
      # @param row [Array]
      # @return [Copying] itself
      # @raise [Error] a value the protocol cannot carry; a connection
      #   failure
      def <<(row)
        raise Error.misused("the copy has ended") if @ended

        cells = by_column_cells(row)
        cells ? by_column(cells) : by_row(row)
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

      # The cells of +row+ if it goes by column: columns granted, each of
      # its values one Copy.cells takes, and as many as those of the rows
      # waiting by column.
      def by_column_cells(row)
        return nil unless @by_column

        cells = Copy.cells(row)
        cells if cells && !cells.empty? && [nil, cells.size].include?(@lanes&.width)
      end

      # Adds +row+ to those by row, the rows waiting by column sent first;
      # a row of a value the protocol cannot carry refused whole.
      def by_row(row)
        written = Protocol::Writer.new
        Protocol::ValueWriter.row_values(written, row)
        flush_lanes
        @waiting.raw(written.to_s)
        @count += 1
        flush if @waiting.size >= Copy::CHUNK_BYTES
        self
      end

      # Adds the row of +cells+ to those by column, the rows waiting by row
      # sent first.
      def by_column(cells)
        flush_rows
        lanes = @lanes ||= Lanes.new(cells.size)
        lanes << cells
        flush_lanes if lanes.size >= Copy::CHUNK_BYTES
        self
      end

      # Sends the rows waiting, by row and by column.
      def flush
        flush_rows
        flush_lanes
      end

      # Sends the rows waiting by row.
      def flush_rows
        return if @count.zero?

        @connection.copy_data(@count, @waiting.to_s)
        @waiting = Protocol::Writer.new
        @count = 0
      end

      # Sends the rows waiting by column.
      def flush_lanes
        lanes = @lanes
        return unless lanes

        @lanes = nil
        @connection.copy_columns(lanes)
      end

      # Sends CopyEnd: the rows inserted.
      def ended(abandon)
        @ended = true
        @connection.copy_end(abandon)
      end
    end
  end
end
