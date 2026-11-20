# frozen_string_literal: true

module Turborel
  # Rows of a source imported into a table over a connection [CLIENT
  # Importing], as turborel-client's import does: through one prepared
  # INSERT, or by copy where the server grants it, a batch committed at a
  # time.
  #
  # A source is any object that answers +headings+, its fields' names and
  # types if it knows them, or +nil+, asked once before the first record;
  # then +record+, the next Record, +nil+ at the end and after. It holds a
  # record at a time, and raises SourceError where it cannot be read on.
  # Delimited reads CSV and tab-separated text.
  module Import
    # How many rows an import commits at a time, unless told.
    DEFAULT_BATCH = 1000

    # Where in a source a record began: its +record+ number, the first 1, a
    # header not counted, and the +line+ it began on, the first 1, of a
    # source of lines, +nil+ of another.
    Position = Data.define(:record, :line)

    # A position's words.
    class Position
      # @return [String] as "record 3, line 4"
      def to_s = line ? "record #{record}, line #{line}" : "record #{record}"
    end

    # What a source says of one of its fields: a +name+, which names a
    # column, and its +type+, a DataType, if it knows one.
    Heading = Data.define(:name, :type)

    # A record of a source: a value for each field, and its Position. A
    # source that knows no types gives Strings, and +nil+ for null; each is
    # cast to its column's type as it is inserted.
    Record = Data.define(:values, :position)

    # What an import is to do: the +table+ its rows go into, as SQL names
    # it; how many rows are committed at a time, +batch+, 0 for all at
    # once; and whether a row refused is skipped and reported, +skip+.
    Options = Data.define(:table, :batch, :skip)

    # Options made for a table.
    class Options
      # Options of an import into +table+, DEFAULT_BATCH rows at a time,
      # stopping at the first row that fails.
      #
      # @param table [String]
      # @return [Options]
      def self.into(table) = new(table:, batch: DEFAULT_BATCH, skip: false)
    end

    # What an import did: the +rows+ inserted and committed, and how many
    # were skipped, +rejected+.
    Imported = Data.define(:rows, :rejected)

    # A row skipped: its Position, and why, +failure+, a Failure of the
    # source's (SQLSTATE 22000) or of SQL.
    Rejected = Data.define(:position, :failure, :input)

    # A rejected row's words.
    class Rejected
      # @return [String] as "record 3: ...; skipped"
      def to_s = "#{position}: #{Import.cause_text(failure, input)}; skipped"
    end

    # Why a source cannot give its next record: what is wrong, and its
    # Position.
    class SourceError < StandardError
      # @return [Position]
      attr_reader :position

      # @param position [Position]
      # @param message [String]
      def initialize(position, message)
        super(message)
        @position = position
      end
    end

    # Why an import stopped, and what of it was kept: a Turborel::Error
    # whose failure is the cause, the source's (SQLSTATE 22000) or SQL's.
    class ImportError < Error
      # @return [Position, nil] where the record that stopped it began
      attr_reader :position

      # @return [Integer] how many rows were committed before
      attr_reader :committed

      # @return [Integer] how many of the batch under way were rolled back
      attr_reader :rolled_back

      # @return [Boolean] whether the source's, not SQL's
      attr_reader :input

      # @api private
      def initialize(failure, position:, committed:, rolled_back:, input:)
        super(failure)
        @position = position
        @committed = committed
        @rolled_back = rolled_back
        @input = input
      end

      # @return [String] as "record 3, line 4: ...; 2 rows committed, 1
      #   rolled back"
      def message
        where = position ? "#{position}: " : ""
        "#{where}#{Import.cause_text(failure, input)}; #{Import.rows(committed)} committed, #{rolled_back} rolled back"
      end
    end

    # Imports +source+'s records into the table +options+ names, over
    # +connection+, as +options+ say; each row skipped is given to the
    # block. The connection's session must have no transaction active, as
    # an import commits its batches.
    #
    # @param connection [Client::Connection]
    # @param source [#headings, #record]
    # @param options [Options]
    # @yieldparam rejected [Rejected]
    # @return [Imported]
    # @raise [ImportError] why it stopped, where, and how many rows were
    #   committed, the batch under way rolled back
    def self.run(connection, source, options, &rejected)
      handler = rejected || ->(_) {}
      Run.start(connection, source, options, handler)
    end

    # +n+ rows, in words: "1 row", "2 rows".
    #
    # @api private
    def self.rows(count) = "#{count} row#{"s" unless count == 1}"

    # A cause as turborel-client's Display writes it: the source's message,
    # or SQL's failure with its SQLCODE and SQLSTATE.
    #
    # @api private
    def self.cause_text(failure, input)
      return failure.message if input

      rule = failure.rule ? " [#{failure.rule}]" : ""
      "SQLCODE #{failure.sqlcode} (SQLSTATE #{failure.sqlstate}): #{failure.message}#{rule}"
    end

    # The failure of the source's +message+.
    #
    # @api private
    def self.input(message) = Error.data_exception(message).failure

    # The failure of SQL's +error+, of a statement the import made, not
    # the user's: so without its position in that statement.
    #
    # @api private
    def self.sql(error) = error.failure.with(position: nil)
  end
end
