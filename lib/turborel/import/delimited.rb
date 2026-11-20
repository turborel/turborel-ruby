# frozen_string_literal: true

module Turborel
  module Import
    # How delimited text is written: its +delimiter+, whether fields may be
    # enclosed in quotes (+quoted+, CSV's), whether the first record names
    # the fields (+header+), what a field not in quotes is written as to
    # be null (+null+), and the longest record in bytes (+max_record+).
    Dialect = Data.define(:delimiter, :quoted, :header, :null, :max_record)

    # A dialect's forms.
    class Dialect
      # [RFC 4180 §2] CSV: fields split at commas, enclosed in quotes as
      # they need; no header; an empty field null.
      #
      # @return [Dialect]
      def self.csv
        new(delimiter: ",", quoted: true, header: false, null: "", max_record: Delimited::DEFAULT_MAX_RECORD)
      end

      # Tab-separated text: fields split at tabs, never quoted.
      #
      # @return [Dialect]
      def self.tsv = csv.with(delimiter: "\t", quoted: false)

      # The dialect, its first record naming the fields [RFC 4180 §2 rule 3].
      def with_header = with(header: true)

      # The dialect, a field written as +null+, not in quotes, null.
      def with_null(null) = with(null:)

      # The dialect, a record at most +bytes+ long, its line break counted.
      def with_max_record(bytes) = with(max_record: bytes)

      # The dialect, its fields split at +delimiter+, one ASCII character
      # not a quote or a line break.
      #
      # @raise [Error] TB910 of another
      def with_delimiter(delimiter)
        unless delimiter.is_a?(String) && delimiter.size == 1 && delimiter.ascii_only? && !"\"\r\n".include?(delimiter)
          raise Error.misused("a delimiter is one ASCII character, not a quote or a line break: #{delimiter.inspect}")
        end

        with(delimiter:)
      end
    end

    # Delimited text read from an IO, a record at a time, so a file of any
    # size is read in bounded memory [CLIENT Importing], as
    # turborel-client's Delimited reads it.
    #
    # CSV [RFC 4180 §2]: a record ends at a line break, CR LF or LF alone,
    # the last optional; a header may come first; a field may be enclosed
    # in double quotes, and must be to hold the delimiter, a quote or a line
    # break, a quote in it written twice. A quote in a field not enclosed,
    # or anything but the delimiter after a closing quote, is refused.
    # Tab-separated text has no quoting. A field written as the null text,
    # not in quotes, is null: by default an empty one, so ,, is a null and
    # ,"", the empty string. Text is UTF-8; a byte order mark beginning
    # the input is passed over.
    class Delimited
      # The longest record read by default, in bytes: the protocol's longest
      # body, as a longer record could not be sent.
      DEFAULT_MAX_RECORD = 16 * 1024 * 1024
      # What encloses a field.
      QUOTE = '"'.b
      # The UTF-8 byte order mark.
      BOM = "\xEF\xBB\xBF".b
      # What a record's scan is in, at each byte.
      FIELD_START = :field_start

      # A source of the text +input+ reads, written as +dialect+ says.
      #
      # @param input [IO, StringIO] read in bytes by gets
      # @param dialect [Dialect]
      def initialize(input, dialect = Dialect.csv)
        @input = input
        @dialect = dialect
        @lines = 0
        @records = 0
        @header_pending = dialect.header
        @started = false
        @done = false
      end

      # The fields' names, of a header; +nil+ without one.
      #
      # @return [Array<Heading>, nil]
      # @raise [SourceError]
      def headings
        return nil unless @header_pending

        @header_pending = false
        fields, = fields(0)
        raise SourceError.new(Position.new(record: 0, line: 1), "there is no header") unless fields

        fields.map { |text, _| Heading.new(name: text, type: nil) }
      end

      # The next record; +nil+ at the end.
      #
      # @return [Record, nil]
      # @raise [SourceError]
      def record
        headings
        return nil if @done

        number = @records + 1
        fields, line = fields(number)
        return nil unless fields

        @records = number
        values = fields.map { |text, quoted| !quoted && text == @dialect.null ? nil : text }
        Record.new(values:, position: Position.new(record: number, line:))
      end

      private

      # The next record's fields, each its text and whether quoted, and the
      # line it began on; +nil+ at the end.
      def fields(number)
        line = @lines + 1
        bytes = raw
        fields = bytes && Delimited.split(bytes, @dialect)
        @done = fields.nil?
        [fields, line]
      rescue SourceError => e
        @done = true
        raise SourceError.new(Position.new(record: number, line:), e.message)
      end

      # The next record's bytes, its line break taken off; +nil+ at the end.
      def raw
        bytes = +"".b
        state = FIELD_START
        while (piece = piece_of(bytes))
          state = Delimited.scanned(state, piece, @dialect) if @dialect.quoted
          @lines += 1
          return taken(bytes) unless state == :quoted
        end
        ended(state, bytes)
      end

      # The next line's bytes, added to +bytes+; +nil+ at the end. A record
      # past the longest is refused rather than read to its end.
      def piece_of(bytes)
        piece = line_of(@dialect.max_record - bytes.bytesize + 1)
        bytes << piece if piece
        raise SourceError.new(nil, "the record is longer than #{@dialect.max_record} bytes") if long?(bytes)

        piece
      end

      # The next line, at most +most+ bytes of it; +nil+ at the end.
      def line_of(most)
        @input.gets("\n", most)&.b
      rescue IOError, SystemCallError => e
        raise SourceError.new(nil, "cannot read: #{e.message}")
      end

      # Whether +bytes+ are past the longest record.
      def long?(bytes) = bytes.bytesize > @dialect.max_record

      # The record at the end of the input: what was read, unless nothing
      # was; a quoted field left open refused.
      def ended(state, bytes)
        raise SourceError.new(nil, Delimited.unclosed) if state == :quoted

        bytes.empty? ? nil : taken(bytes)
      end

      # +bytes+, a record, its line break and the input's byte order mark
      # taken off.
      def taken(bytes)
        bytes = bytes.delete_suffix("\n").delete_suffix("\r") if bytes.end_with?("\n")
        bytes = bytes.byteslice(BOM.bytesize, bytes.bytesize) || "".b if !@started && bytes.start_with?(BOM)
        @started = true
        bytes
      end

      class << self
        # Where a scan of a CSV record is after +piece+, from +state+.
        #
        # @api private
        def scanned(state, piece, dialect)
          delimiter = dialect.delimiter.ord
          piece.each_byte.reduce(state) { |was, byte| step(was, byte == QUOTE.ord, byte == delimiter) }
        end

        # The state after a byte, a quote or a delimiter.
        #
        # @api private
        def step(state, quote, split)
          case state
          when :quoted then quote ? :quote_in_quoted : :quoted
          when :plain then split ? FIELD_START : :plain
          else
            return FIELD_START if split

            quote ? :quoted : :plain
          end
        end

        # The fields of the record +bytes+, each its text and whether it
        # was quoted.
        #
        # @api private
        def split(bytes, dialect)
          return unquoted(bytes, dialect) unless dialect.quoted

          fields = [] #: Array[[String, bool]]
          at = 0
          loop do
            n = fields.size
            quoted = bytes.byteslice(at, 1) == QUOTE
            written, at = quoted ? enclosed(bytes, at + 1, n) : plain(bytes, at, dialect.delimiter.b, n)
            fields << [text(written, n), quoted]
            return fields if at >= bytes.bytesize

            at = past_delimiter(bytes, at, dialect, n)
          end
        end

        # The fields of a record of a dialect with no quoting: an empty
        # record one empty field, as Rust's split gives it.
        #
        # @api private
        def unquoted(bytes, dialect)
          parts = bytes.split(dialect.delimiter.b, -1)
          (parts.empty? ? ["".b] : parts).each_with_index.map { |b, n| [text(b, n), false] }
        end

        # Where the field after the field +number+, ending at +at+, begins:
        # past its delimiter, which must come next.
        #
        # @api private
        def past_delimiter(bytes, at, dialect, number)
          return at + 1 if bytes.byteslice(at, 1) == dialect.delimiter.b

          raise SourceError.new(nil, "[RFC 4180 §2 rule 5] field #{number + 1}: a quoted field's closing quote " \
                                     "is followed by more")
        end

        # A field not in quotes from +at+ to the next delimiter, and where
        # it ends.
        #
        # @api private
        def plain(bytes, at, delimiter, number)
          ending = bytes.index(delimiter, at) || bytes.bytesize
          written = bytes.byteslice(at, ending - at) || "".b
          if written.include?(QUOTE)
            raise SourceError.new(nil,
                                  "[RFC 4180 §2 rule 5] field #{number + 1}: a quote in a field not enclosed in quotes")
          end

          [written, ending]
        end

        # A field in quotes, its opening quote read, to its closing quote,
        # a quote written twice in it one, and where it ends.
        #
        # @api private
        def enclosed(bytes, at, number)
          written = +"".b
          loop do
            found = bytes.index(QUOTE, at)
            raise SourceError.new(nil, "field #{number + 1}: #{unclosed}") unless found

            written << (bytes.byteslice(at, found - at) || "")
            return [written, found + 1] unless bytes.byteslice(found + 1, 1) == QUOTE

            written << QUOTE
            at = found + 2
          end
        end

        # +bytes+ as text, of the field of index +number+.
        #
        # @api private
        def text(bytes, number)
          text = bytes.dup.force_encoding(Encoding::UTF_8)
          raise SourceError.new(nil, "field #{number + 1} is not UTF-8") unless text.valid_encoding?

          text
        end

        # The message of a quoted field not closed.
        #
        # @api private
        def unclosed = "[RFC 4180 §2 rule 5] a quoted field is not closed"
      end
    end
  end
end
