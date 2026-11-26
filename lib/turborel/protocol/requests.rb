# frozen_string_literal: true

module Turborel
  module Protocol
    # Every request the client sends, encoded as a frame [PROTOCOL
    # Requests], each as its section lays it out. A tail field is written
    # only where it has something to say, so a request with none is its
    # first form exactly [PROTOCOL The tail].
    #
    # @api private
    module Requests
      # The protocol's version, the first field of Hello [PROTOCOL Hello 'H'].
      VERSION = 1
      # The kinds of the requests [PROTOCOL Requests].
      HELLO = "H".ord
      # (see HELLO)
      ANSWER = "A".ord
      # (see HELLO)
      QUERY = "Q".ord
      # (see HELLO)
      PREPARE = "P".ord
      # (see HELLO)
      EXECUTE = "E".ord
      # (see HELLO)
      FETCH = "F".ord
      # (see HELLO)
      CLOSE = "C".ord
      # (see HELLO)
      DEALLOCATE = "D".ord
      # (see HELLO)
      LOB = "L".ord
      # (see HELLO)
      CANCEL = "Z".ord
      # (see HELLO)
      TERMINATE = "X".ord
      # (see HELLO)
      DESCRIBE = "Y".ord
      # (see HELLO)
      PING = "G".ord
      # (see HELLO)
      RESET = "W".ord
      # (see HELLO)
      CHANGE_USER = "U".ord
      # (see HELLO)
      COPY_IN = "I".ord
      # (see HELLO)
      COPY_DATA = "J".ord
      # (see HELLO)
      COPY_END = "N".ord
      # (see HELLO)
      DEBUG = "V".ord
      # (see HELLO)
      COPY_COLUMNS = "O".ord
      # A Lob request's operations [PROTOCOL Requests].
      LOB_READ = 0
      # (see LOB_READ)
      LOB_CREATE = 1
      # (see LOB_READ)
      LOB_APPEND = 2
      # (see LOB_READ)
      LOB_FREE = 3
      # (see LOB_READ)
      LOB_HOLD = 4
      # What a Debug request asks [PROTOCOL Debug 'V'].
      DEBUG_IDENTIFY = 0
      # (see DEBUG_IDENTIFY)
      DEBUG_ATTACH = 1
      # (see DEBUG_IDENTIFY)
      DEBUG_DETACH = 2
      # (see DEBUG_IDENTIFY)
      DEBUG_BREAK = 3
      # (see DEBUG_IDENTIFY)
      DEBUG_CLEAR = 4
      # (see DEBUG_IDENTIFY)
      DEBUG_BREAKPOINTS = 5
      # (see DEBUG_IDENTIFY)
      DEBUG_RESUME = 6
      # (see DEBUG_IDENTIFY)
      DEBUG_INTERRUPT = 7
      # (see DEBUG_IDENTIFY)
      DEBUG_STACK = 8
      # What a Describe describes.
      DESCRIBE_STATEMENT = 0
      # (see DESCRIBE_STATEMENT)
      DESCRIBE_CURSOR = 1
      # The bytes of a cancel key.
      KEY_BYTES = 16
      # No attributes.
      NO_ATTRIBUTES = Array.new(0).freeze

      # Hello: version u32, user, mechanism, the mechanism's first bytes,
      # the capabilities asked for, then tail 1, the attributes.
      #
      # @return [String] the frame
      def self.hello(user:, mechanism:, initial:, capabilities:, attributes: NO_ATTRIBUTES)
        writer = Writer.new.u32(VERSION).str(user).str(mechanism).bytes(initial).strs(capabilities)
        Tail.put_attributes(writer, attributes)
        Frame.encode(HELLO, writer.to_s)
      end

      # @param answer [String] the answer to a Challenge
      # @return [String] the frame of Answer
      def self.answer(answer) = Frame.encode(ANSWER, Writer.new.bytes(answer).to_s)

      # Query: sql, ends flag, then tail 1, the attributes, and 2, multi.
      #
      # @return [String] the frame
      def self.query(sql, ends:, attributes: NO_ATTRIBUTES, multi: false)
        writer = Writer.new.str(sql).flag(ends)
        Tail.put_attributes(writer, attributes)
        writer.u8(Tail::MULTI) if multi
        Frame.encode(QUERY, writer.to_s)
      end

      # @param statement [Integer] the client's number for it
      # @param sql [String]
      # @return [String] the frame of Prepare
      def self.prepare(statement, sql) = Frame.encode(PREPARE, Writer.new.u32(statement).str(sql).to_s)

      # Execute: statement u32, a row of values, rows u32 (0 for all), ends
      # flag, then tail 1, the attributes, and 3, the cursor, unless 0.
      #
      # @param statement [Integer]
      # @param values [Array] one value for each parameter
      # @param tail [Hash] +:attributes+ and +:cursor+, each optional
      # @return [String] the frame
      def self.execute(statement, values, rows:, ends:, tail: {})
        writer = Writer.new.u32(statement)
        ValueWriter.row_values(writer, values)
        writer.u32(rows).flag(ends)
        Tail.put_attributes(writer, tail.fetch(:attributes, NO_ATTRIBUTES))
        put_cursor(writer, tail.fetch(:cursor, 0))
        Frame.encode(EXECUTE, writer.to_s)
      end

      # @return [String] the frame of Fetch: statement, rows, then tail 3
      def self.fetch(statement, rows:, cursor: 0)
        Frame.encode(FETCH, put_cursor(Writer.new.u32(statement).u32(rows), cursor).to_s)
      end

      # @return [String] the frame of Close: statement, then tail 3
      def self.close(statement, cursor: 0) = Frame.encode(CLOSE, put_cursor(Writer.new.u32(statement), cursor).to_s)

      # @return [String] the frame of Deallocate
      def self.deallocate(statement) = Frame.encode(DEALLOCATE, Writer.new.u32(statement).to_s)

      # @return [String] the frame of Lob's read: locator, from, count,
      #   characters flag
      def self.lob_read(locator, from, count, characters:)
        lob(Writer.new.u8(LOB_READ).u32(locator).u64(from).u64(count).flag(characters))
      end

      # @param kind [Symbol] +:character+ or +:binary+
      # @return [String] the frame of Lob's create
      def self.lob_create(kind)
        byte = Values::LOB_KINDS.key(kind)
        raise Error.misused("#{kind.inspect} is no kind of large object") unless byte

        lob(Writer.new.u8(LOB_CREATE).u8(byte))
      end

      # @return [String] the frame of Lob's append: locator, then bytes
      def self.lob_append(locator, octets) = lob(Writer.new.u8(LOB_APPEND).u32(locator).bytes(octets))

      # @return [String] the frame of Lob's free
      def self.lob_free(locator) = lob(Writer.new.u8(LOB_FREE).u32(locator))

      # @return [String] the frame of Lob's hold
      def self.lob_hold(locator) = lob(Writer.new.u8(LOB_HOLD).u32(locator))

      # @return [String] the frame of Debug's identify, stack, breakpoints,
      #   detach or interrupt: +what+ alone [PROTOCOL Debug 'V']
      def self.debug(what) = Frame.encode(DEBUG, Writer.new.u8(what).to_s)

      # @return [String] the frame of Debug's attach: a connection's ID u64
      def self.debug_attach(id) = Frame.encode(DEBUG, Writer.new.u8(DEBUG_ATTACH).u64(id).to_s)

      # Debug's break: kind u8, schema, name, line u32, then the condition
      # if given, after its flag.
      #
      # @param kind [Symbol] +:procedure+, +:function+ or +:trigger+
      # @param schema [String] empty for the session's default
      # @param name [String]
      # @param line [Integer] from 1
      # @param condition [String, nil]
      # @return [String] the frame
      def self.debug_break(kind, schema, name, line, condition)
        code = Debug::KINDS.fetch(kind) { raise Error.misused("#{kind.inspect} is no kind of routine") }
        writer = Writer.new.u8(DEBUG_BREAK).u8(code).str(schema).str(name).u32(line).flag(!condition.nil?)
        writer.str(condition) if condition
        Frame.encode(DEBUG, writer.to_s)
      end

      # @return [String] the frame of Debug's clear: a breakpoint's number
      def self.debug_clear(number) = Frame.encode(DEBUG, Writer.new.u8(DEBUG_CLEAR).u32(number).to_s)

      # @param action [Symbol] +:into+, +:over+, +:out+ or +:continue+
      # @return [String] the frame of Debug's resume: the action u8
      def self.debug_resume(action)
        code = Debug::ACTIONS.fetch(action) { raise Error.misused("#{action.inspect} is no way to go on") }
        Frame.encode(DEBUG, Writer.new.u8(DEBUG_RESUME).u8(code).to_s)
      end

      # @param key [String] the 16 bytes Ready gave
      # @return [String] the frame of Cancel
      def self.cancel(key)
        raise Error.misused("a cancel key is 16 bytes") unless key.bytesize == KEY_BYTES

        Frame.encode(CANCEL, key.b)
      end

      # @return [String] the frame of Terminate, a header alone
      def self.terminate = Frame.encode(TERMINATE, "")

      # @return [String] the frame of Describe of a prepared statement
      def self.describe_statement(statement)
        Frame.encode(DESCRIBE, Writer.new.u8(DESCRIBE_STATEMENT).u32(statement).u32(0).to_s)
      end

      # @return [String] the frame of Describe of an open cursor
      def self.describe_cursor(statement, cursor)
        Frame.encode(DESCRIBE, Writer.new.u8(DESCRIBE_CURSOR).u32(statement).u32(cursor).to_s)
      end

      # @return [String] the frame of Ping, a header alone
      def self.ping = Frame.encode(PING, "")

      # @return [String] the frame of Reset, a header alone
      def self.reset = Frame.encode(RESET, "")

      # @return [String] the frame of ChangeUser: user, mechanism, initial
      def self.change_user(user, mechanism, initial)
        Frame.encode(CHANGE_USER, Writer.new.str(user).str(mechanism).bytes(initial).to_s)
      end

      # @param table [String] the table as SQL names it
      # @param columns [Array<String>] none for every column in order
      # @return [String] the frame of CopyIn
      def self.copy_in(table, columns, ends:)
        Frame.encode(COPY_IN, Writer.new.str(table).strs(columns).flag(ends).to_s)
      end

      # @param rows [Array<Array>] rows of values
      # @return [String] the frame of CopyData: a list of rows
      def self.copy_data(rows)
        writer = Writer.new.u32(rows.size)
        rows.each { |row| ValueWriter.row_values(writer, row) }
        Frame.encode(COPY_DATA, writer.to_s)
      end

      # CopyColumns: rows u32, then a column for each of the copy's, in
      # order, each its null bits, its ends and its text [PROTOCOL
      # CopyColumns 'O'].
      #
      # @param rows [Integer]
      # @param columns [Array<Array(String, Array<Integer>, String)>] each
      #   column's null bits, row 0 the low bit of the first byte; where
      #   each row's cell ends in its text; and its text, UTF-8
      # @return [String] the frame
      def self.copy_columns(rows, columns)
        writer = Writer.new.u32(rows).u32(columns.size)
        columns.each do |nulls, ends, text|
          writer.bytes(nulls).u32(ends.size)
          ends.each { writer.u32(_1) }
          writer.bytes(text)
        end
        Frame.encode(COPY_COLUMNS, writer.to_s)
      end

      # @return [String] the frame of CopyEnd
      def self.copy_end(abandon:) = Frame.encode(COPY_END, Writer.new.flag(abandon).to_s)

      # Writes tail 3, the cursor, unless it is 0.
      #
      # @return [Writer]
      def self.put_cursor(writer, cursor)
        writer.u8(Tail::CURSOR).u32(cursor) unless cursor.zero?
        writer
      end

      # @return [String] the frame of Lob, of the body +writer+ wrote
      def self.lob(writer) = Frame.encode(LOB, writer.to_s)
    end
  end
end
