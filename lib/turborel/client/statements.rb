# frozen_string_literal: true

module Turborel
  module Client
    # A connection's statements [CLIENT Running statements], [CLIENT
    # Prepared statements]: a statement run whole, its rows read at once or
    # a batch at a time; and prepared statements, executed, their cursors
    # opened, fetched and closed, numbered with cursors, described.
    module Statements
      # Runs +sql+, a direct SQL statement, in the connection's session: a
      # query's Rows, or another statement's Completion; under autocommit
      # the transaction ended with it [PROTOCOL Query 'Q'].
      #
      # @param sql [String]
      # @return [Rows, Completion]
      # @raise [Error] the statement's, as the server reports it; a
      #   connection failure
      def query(sql)
        send_frame(Protocol::Requests.query(sql, ends: @autocommit, attributes: carried_attributes))
        outcome.first
      end

      # Runs +sql+ as query does, a query's columns and then its rows given
      # to +sink+ a batch at a time, as they come, so no more than a batch
      # is held [CLIENT Running statements]: +sink+ answers +columns+ and
      # +rows+.
      #
      # @param sql [String]
      # @param sink [#columns, #rows]
      # @return [Integer, Completion] how many rows went to the sink, or
      #   another statement's Completion
      # @raise [Error] as query's; a query's failure after some rows went
      #   to the sink
      def query_into(sql, sink)
        send_frame(Protocol::Requests.query(sql, ends: @autocommit, attributes: carried_attributes))
        first = expect(Protocol::Replies::Complete, Protocol::Replies::Description)
        return first if first.is_a?(Protocol::Replies::Complete)

        sink.columns(first.columns)
        streamed(sink)
      end

      # Prepares +sql+, its dynamic parameters written ? [PROTOCOL Prepare
      # 'P'].
      #
      # @param sql [String]
      # @return [Statement]
      # @raise [Error] the server's: SQLSTATE 37000 if it is not
      #   preparable; a connection failure
      def prepare(sql)
        number = @next_statement
        @next_statement = (@next_statement + 1) & Protocol::Writer::MAX_U32
        send_frame(Protocol::Requests.prepare(number, sql))
        prepared
      end

      # Executes +statement+ with +values+, one for each parameter: a
      # query's Rows, all of them, or another statement's Completion; under
      # autocommit the transaction ended with it [PROTOCOL Execute 'E'].
      #
      # @param statement [Statement]
      # @param values [Array]
      # @return [Rows, Completion]
      # @raise [Error] the server's: SQLSTATE 07001 if the values are not
      #   one for each parameter; the statement's; a connection failure
      def execute(statement, values = [])
        execute_frame(statement, values, 0, @autocommit, { attributes: carried_attributes })
        return completion_reply if statement.columns.empty?

        Rows.new(columns: statement.columns, rows: rows_until_end.first)
      end

      # Opens the cursor of +statement+, a query, with +values+, and gives
      # at most +rows+ of its rows, all if 0. Under autocommit, granted
      # fetch-ends, the transaction ends as the cursor does [CLIENT What the
      # server tells].
      #
      # @param statement [Statement]
      # @param values [Array]
      # @param rows [Integer]
      # @return [Batch]
      # @raise [Error] the server's: 24000 if its cursor is open; as
      #   execute's
      def open_cursor(statement, values = [], rows = 0) = open_cursor_numbered(statement, 0, values, rows)

      # Opens the cursor numbered +cursor+ of +statement+, as open_cursor
      # opens its one: several open at once, each of its own number, once
      # cursors is granted; 0 is open_cursor's [PROTOCOL Execute 'E'].
      #
      # @return [Batch]
      # @raise [Error] as open_cursor's; a connection failure of a number
      #   other than 0 if cursors was not granted
      def open_cursor_numbered(statement, cursor, values = [], rows = 0)
        needs(cursor.zero?, Protocol::Capabilities::CURSORS)
        ends = @autocommit && @granted.include?(Protocol::Capabilities::FETCH_ENDS)
        execute_frame(statement, values, rows, ends, { attributes: carried_attributes, cursor: })
        batch
      end

      # At most +rows+ more rows of +statement+'s cursor numbered
      # +cursor+, all if 0 [PROTOCOL Fetch 'F'].
      #
      # @return [Batch]
      # @raise [Error] the server's: 24000 if the cursor is not open; a
      #   connection failure
      def fetch(statement, rows = 0, cursor: 0)
        needs(cursor.zero?, Protocol::Capabilities::CURSORS)
        send_frame(Protocol::Requests.fetch(statement.number, rows:, cursor:))
        batch
      end

      # Closes +statement+'s cursor numbered +cursor+ [PROTOCOL Close 'C'].
      #
      # @return [void]
      # @raise [Error] the server's: 24000 if it is not open; a connection
      #   failure
      def close(statement, cursor: 0)
        needs(cursor.zero?, Protocol::Capabilities::CURSORS)
        send_frame(Protocol::Requests.close(statement.number, cursor:))
        completion_reply
        nil
      end

      # Destroys +statement+ [PROTOCOL Deallocate 'D'].
      #
      # @return [void]
      # @raise [Error] the server's: 26000 if there is no such statement,
      #   24000 if a cursor of it is open; a connection failure
      def deallocate(statement)
        send_frame(Protocol::Requests.deallocate(statement.number))
        completion_reply
        nil
      end

      # +statement+ described again by the server, as it is now [PROTOCOL
      # Describe 'Y'].
      #
      # @return [Statement]
      # @raise [Error] the server's: 26000 if it is no more; a connection
      #   failure if describe was not granted
      def describe(statement)
        needs(false, Protocol::Capabilities::DESCRIBE)
        send_frame(Protocol::Requests.describe_statement(statement.number))
        prepared
      end

      # The columns of +statement+'s open cursor numbered +cursor+
      # [PROTOCOL Describe 'Y'].
      #
      # @return [Array<Column>]
      # @raise [Error] the server's: 24000 if it is not open; a connection
      #   failure if describe was not granted
      def describe_cursor(statement, cursor = 0)
        needs(false, Protocol::Capabilities::DESCRIBE)
        send_frame(Protocol::Requests.describe_cursor(statement.number, cursor))
        # Its Description is its last reply, as no rows follow it.
        expect(Protocol::Replies::Description, answer: :one).columns
      end

      private

      # Sends the Execute of +statement+ with +values+.
      def execute_frame(statement, values, rows, ends, tail)
        send_frame(Protocol::Requests.execute(statement.number, values, rows:, ends:, tail:))
      end

      # The Statement the server's Prepared describes.
      def prepared
        reply = expect(Protocol::Replies::Prepared)
        Statement.new(number: reply.statement, parameters: reply.parameters, columns: reply.columns)
      end

      # A cursor's Batch.
      def batch
        rows, ended = rows_until_end
        Batch.new(rows:, more: ended.nil?)
      end

      # Gives the sink each batch of rows until the Complete.
      def streamed(sink)
        count = 0
        loop do
          reply = expect(Protocol::Replies::Rows, Protocol::Replies::Complete)
          return count if reply.is_a?(Protocol::Replies::Complete)

          rows = reply.rows #: Array[Array[value]]
          count += rows.size
          sink.rows(rows)
        end
      end
    end
  end
end
