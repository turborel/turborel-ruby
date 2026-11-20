# frozen_string_literal: true

module Turborel
  module Import
    # An import by copy (turborel-client's copied.rs): its rows checked as
    # the INSERT's parameters take them, then sent a batch to a copy, each
    # copy committing its batch as it ends. A row the server refuses fails
    # its copy, every row of the batch undone, the failure's detail naming
    # the row, so the import says its record as it would of a row inserted
    # alone.
    #
    # @api private
    class Copied
      # What the detail of a row a copy refused is: "row 7 of the copy".
      ROW = /\Arow (\d+) of the copy\z/
      # The kinds of the large object types, whose columns an import does
      # not copy.
      LOB_TYPES = %i[clob blob].freeze

      # Whether an import into +insert+'s parameters goes by copy: copy
      # granted, no bad row skipped, no large object column.
      def self.copies?(connection, insert, options)
        connection.granted?(Protocol::Capabilities::COPY) && !options.skip &&
          insert.parameters.none? { |parameter| LOB_TYPES.include?(parameter.type.kind) }
      end

      # Runs the import by copy, the INSERT, its parameters' types known,
      # let go first.
      #
      # @return [Imported]
      def self.start(connection, source, options, insert, columns)
        table = Run.named(options.table)
        Run.sql_step { connection.deallocate(insert) }
        run = new(connection, options, insert.parameters, [table, columns])
        nil while run.copied(source)
        Imported.new(rows: run.committed, rejected: 0)
      end

      # @return [Integer] the rows committed
      attr_reader :committed

      # An import by copy into the table and columns +into+.
      def initialize(connection, options, parameters, into)
        @connection = connection
        @options = options
        @parameters = parameters
        @table, @columns = into
        @committed = 0
        @batch = [] #: Array[Position]
      end

      # Copies a batch of the source's records, its copy begun at its first
      # record and ended at its last: whether records may follow.
      def copied(source)
        first = checked(source)
        return false unless first

        copy = begin
          @connection.copy_begin(@table, @columns, true)
        rescue Error => e
          raise stop(nil, Import.sql(e), 0, false)
        end
        within(copy) { batch(copy, source, first) }
      end

      private

      # The block's result; the copy abandoned if it fails before the copy
      # ends, so the connection takes requests again.
      def within(copy)
        yield
      rescue ImportError
        unless copy.ended? || @connection.lost?
          begin
            copy.abandon
          rescue Error
            nil
          end
        end
        raise
      end

      # Sends the batch's records, then ends its copy.
      def batch(copy, source, first)
        record = first
        loop do
          position, values = record
          sent(copy, position, values)
          @batch << position
          return ended(copy) || true if @batch.size == @options.batch

          following = checked(source)
          break unless following

          record = following
        end
        ended(copy) || false
      end

      # Sends a row to the copy.
      def sent(copy, position, values)
        copy << values
      rescue Error => e
        raise stop(position, Import.sql(e), @batch.size, false)
      end

      # The next record checked as the INSERT's parameters take it: where
      # it began, and its values; +nil+ at the end.
      def checked(source)
        record = begin
          source.record
        rescue SourceError => e
          raise stop(e.position, Import.input(e.message), @batch.size, true)
        end
        return nil unless record

        [record.position, values_of(record)]
      end

      # The values of +record+, as the parameters take them.
      def values_of(record)
        fields = Run.fields_wrong(record, @parameters.size)
        raise stop(record.position, Import.input(fields), @batch.size, true) if fields

        assigned(record)
      end

      # The values of +record+ assigned to the parameters' types.
      def assigned(record)
        Assign.assigned(record.values, @parameters)
      rescue Error => e
        raise stop(record.position, Import.sql(e), @batch.size, false)
      end

      # Ends the batch's copy: its rows committed, or why it failed, at the
      # row it names. Gives +nil+.
      def ended(copy)
        @committed += copy.finish
        @batch.clear
        nil
      rescue Error => e
        row = row_of(e.failure)
        raise stop(nil, Import.sql(e), @batch.size, false) unless row

        raise stop(@batch[row - 1], Import.sql(e), row - 1, false)
      end

      # The row of the copy +failure+ names, from 1, within the batch.
      def row_of(failure)
        found = ROW.match(failure.diagnostics&.detail.to_s)
        number = found && Integer(found[1].to_s, 10)
        number if number&.between?(1, @batch.size)
      end

      # The import's failure at +position+, +rolled_back+ rows of the
      # batch undone.
      def stop(position, failure, rolled_back, input)
        ImportError.new(failure, position:, committed: @committed, rolled_back:, input:)
      end
    end
  end
end
