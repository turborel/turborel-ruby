# frozen_string_literal: true

module Turborel
  module Client
    # A connection's exports [CLIENT Copying and exporting]: a query's rows
    # streamed from the server and written as they come, a batch at a time,
    # as CSV or as the protocol's own frames.
    module Export
      # The formats an export writes.
      FORMATS = %i[csv native].freeze

      # Runs the query +sql+ and writes its rows to +out+, anything that
      # takes write, as they come: as +:csv+ [RFC 4180], a header of the
      # columns' names then a record for each row, each value as turborel
      # shows it, a null an empty field and an empty string ""; or as
      # +:native+, the protocol's own frames, a Description, Rows and a
      # Complete, which Export.read_native reads back.
      #
      # @param sql [String]
      # @param out [#write]
      # @param format [Symbol]
      # @return [Integer] the rows written
      # @raise [Error] the query's; a connection failure of a statement
      #   that is no query, or a write to +out+ that failed; TB910 of
      #   another format
      def export(sql, out, format = :csv)
        raise Error.misused("#{format.inspect} is no format of an export") unless FORMATS.include?(format)

        sink = format == :csv ? CsvSink.new(out) : NativeSink.new(out)
        count = query_into(sql, sink)
        raise Error.connection_failure("an export runs a query") unless count.is_a?(Integer)

        sink.finish
        count
      end

      # The columns and rows of native rows read from +input+, a String or
      # anything that takes read.
      #
      # @param input [String, #read]
      # @return [Array(Array<Column>, Array<Array>)]
      # @raise [Error] a connection failure of input that is not native
      #   rows, or cut short
      def self.read_native(input)
        reader = NativeReader.new(input.is_a?(String) ? input.b : input.read.to_s.b)
        columns = reader.first_columns
        rows = [] #: Array[Array[value]]
        loop do
          reply = reader.next_reply
          return [columns, rows] if reply.is_a?(Protocol::Replies::Complete)
          unless reply.is_a?(Protocol::Replies::Rows)
            raise Export.not_native("a frame other than Rows before the Complete")
          end

          rows.concat(reply.rows)
        end
      end

      # Flushes +out+, if it flushes.
      #
      # @api private
      def self.flushed(out)
        flushing = _ = out
        flushing.flush if flushing.respond_to?(:flush)
      end

      # The failure of input that is not native rows.
      #
      # @api private
      def self.not_native(why) = Error.connection_failure("not native rows: #{why}")
    end

    # A query's rows written as CSV as they come [CLIENT Copying and
    # exporting].
    #
    # @api private
    class CsvSink
      # What makes a field quoted.
      QUOTED = /[,"\n\r]|\A[[:space:]]|[[:space:]]\z/

      # A sink writing to +out+.
      def initialize(out)
        @out = out
        @types = [] #: Array[DataType]
      end

      # Writes the header.
      def columns(columns)
        @types = columns.map(&:type)
        record(columns.map { |column| field(column.name.to_s) })
      end

      # Writes a record for each row.
      def rows(rows)
        @out.write(rows.map { |row| line(row) }.join)
      rescue Error
        raise
      rescue StandardError => e
        raise Error.connection_failure("cannot write the export: #{e.message}")
      end

      # Ends the export.
      def finish = Export.flushed(@out)

      private

      # The record of +row+.
      def line(row)
        fields = row.each_with_index.map { |value, i| value.nil? ? "" : field(Text.of(value, @types[i])) }
        "#{fields.join(",")}\r\n"
      end

      # Writes the record of +fields+.
      def record(fields) = @out.write("#{fields.join(",")}\r\n")

      # +text+ as CSV writes it: quoted where it must be.
      def field(text) = text.empty? || QUOTED.match?(text) ? "\"#{text.gsub('"', '""')}\"" : text
    end

    # A query's rows written as the protocol's own frames as they come.
    #
    # @api private
    class NativeSink
      # A sink writing to +out+.
      def initialize(out) = @out = out

      # Writes a Description.
      def columns(columns)
        writer = Protocol::Writer.new.u32(columns.size)
        columns.each { |column| Protocol::TypeWriter.column(writer, column) }
        @out.write(Protocol::Frame.encode("D".ord, writer.to_s))
      end

      # Writes Rows.
      def rows(rows)
        writer = Protocol::Writer.new.u32(rows.size)
        rows.each { |row| Protocol::ValueWriter.row_values(writer, row) }
        @out.write(Protocol::Frame.encode("B".ord, writer.to_s))
      end

      # Writes the Complete that ends them.
      def finish
        @out.write(Protocol::Frame.encode("K".ord, Protocol::Writer.new.i32(0).str("00000").flag(false).to_s))
        Export.flushed(@out)
      end
    end

    # Native rows read back, a frame at a time.
    #
    # @api private
    class NativeReader
      # A reader of +bytes+.
      def initialize(bytes)
        @bytes = bytes
        @at = 0
      end

      # The columns of the Description that must come first.
      def first_columns
        reply = next_reply
        raise Export.not_native("no Description first") unless reply.is_a?(Protocol::Replies::Description)

        reply.columns
      end

      # The next frame, decoded.
      def next_reply
        header = @bytes.byteslice(@at, Protocol::Frame::HEADER_BYTES) || ""
        raise Export.not_native("cut short") if header.bytesize < Protocol::Frame::HEADER_BYTES

        kind, length = Protocol::Frame.decode_header(header, Protocol::Frame::MAX_BODY)
        body = @bytes.byteslice(@at + Protocol::Frame::HEADER_BYTES, length) || ""
        raise Export.not_native("cut short") if body.bytesize < length

        @at += Protocol::Frame::HEADER_BYTES + length
        Protocol::Replies.decode(kind, body)
      end
    end
  end
end
