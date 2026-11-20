# frozen_string_literal: true

module Turborel
  module Import
    # An import under way through one prepared INSERT (turborel-client's
    # insert.rs): its columns the source's headings, or else the table's;
    # each value cast by the server to its column's type, but a string for
    # a character string column assigned to it as INSERT assigns; a long
    # string for a large object column sent ahead by a locator. A batch of
    # rows is committed at a time; a failure rolls the batch back and
    # stops, or, if asked, a bad row is skipped and reported.
    #
    # @api private
    class Run
      # SQLCODE of a statement cancelled.
      CANCELLED = -920
      # The large object kind of each large object type.
      LOB_KINDS = { clob: :character, blob: :binary }.freeze

      # Prepares the import and runs it, by copy where it may.
      #
      # @return [Imported]
      def self.start(connection, source, options, rejected)
        insert, columns = prepared(connection, source, options)
        return Copied.start(connection, source, options, insert, columns) if Copied.copies?(connection, insert, options)

        new(connection, insert, options, rejected).imported(source)
      end

      # The INSERT that puts the source's records into the table, prepared,
      # and its columns as SQL names them.
      def self.prepared(connection, source, options)
        if connection.in_transaction?
          raise before("an import begins with no transaction active, as it commits its batches")
        end

        table = named(options.table)
        names = columns(connection, source, table).map { |name| Names.delimited(name) }
        sql = "INSERT INTO #{table} (#{names.join(", ")}) VALUES (#{(["?"] * names.size).join(", ")})"
        [sql_step { connection.prepare(sql) }, names]
      end

      # The columns the source's records go into: its headings', or else
      # the table's.
      def self.columns(connection, source, table)
        headings = begin
          source.headings
        rescue SourceError => e
          raise ImportError.new(Import.input(e.message), position: e.position, committed: 0, rolled_back: 0,
                                                         input: true)
        end
        headings ? headings.map { |heading| Names.column_name(heading.name) } : described(connection, table)
      end

      # What is wrong with +record+'s fields for +wanted+ columns, +nil+ if
      # nothing.
      def self.fields_wrong(record, wanted)
        "#{record.values.size} fields, for #{wanted} columns" unless record.values.size == wanted
      end

      # The table's name as SQL text, or the import refused.
      def self.named(table)
        Names.table_name(table)
      rescue SourceError => e
        raise before(e.message)
      end

      # The names of +table+'s columns, in order, as a query's description
      # gives them.
      def self.described(connection, table)
        query = sql_step { connection.prepare("SELECT * FROM #{table}") }
        sql_step { connection.deallocate(query) }
        query.columns.map { |column| column.name.to_s }
      end

      # The block's result; its Error the import's, before any row.
      def self.sql_step
        yield
      rescue ImportError
        raise
      rescue Error => e
        raise ImportError.new(Import.sql(e), position: nil, committed: 0, rolled_back: 0, input: false)
      end

      # An import's failure of the source's +message+, before any row.
      def self.before(message)
        ImportError.new(Import.input(message), position: nil, committed: 0, rolled_back: 0, input: true)
      end

      # An import over +connection+ through +insert+.
      def initialize(connection, insert, options, rejected)
        @connection = connection
        @insert = insert
        @options = options
        @rejected = rejected
        @committed = 0
        @in_batch = 0
        @skipped = 0
      end

      # Inserts each record, commits the last batch, and lets the INSERT go.
      def imported(source)
        freed = nil #: ImportError?
        done = begin
          rows(source)
        ensure
          freed = deallocated unless @connection.lost?
        end
        raise freed if freed

        done
      end

      private

      # Lets the INSERT go, even if the import stopped: its failure, if any.
      def deallocated
        @connection.deallocate(@insert)
        nil
      rescue Error => e
        ImportError.new(Import.sql(e), position: nil, committed: @committed, rolled_back: 0, input: false)
      end

      # Inserts each record, then commits the last batch.
      def rows(source)
        loop do
          record = begin
            source.record
          rescue SourceError => e
            raise stop(e.position, Import.input(e.message), true)
          end
          break unless record

          row(record)
        end
        commit
        Imported.new(rows: @committed, rejected: @skipped)
      end

      # Inserts +record+, committing its batch if it ends one.
      def row(record)
        fields = Run.fields_wrong(record, @insert.parameters.size)
        return reject(record.position, Import.input(fields), true) if fields

        begin
          values = located(Assign.assigned(record.values, @insert.parameters))
          @connection.execute(@insert, values)
        rescue Error => e
          return failed(record, e)
        end
        @in_batch += 1
        commit if @in_batch == @options.batch
      end

      # A row that failed: skipped if it alone was undone, the batch's
      # transaction going on, and the connection; else the import stopped.
      def failed(record, error)
        alone = @in_batch.zero? || @connection.in_transaction?
        if !alone || Client::Wire.ends_connection?(error.failure) || error.sqlcode == CANCELLED
          raise stop(record.position, Import.sql(error), false)
        end

        reject(record.position, Import.sql(error), false)
      end

      # +values+, each long string for a large object parameter sent ahead
      # a piece at a time and given by its locator, so no request holds it
      # whole.
      def located(values)
        values.each_with_index.map do |value, index|
          kind = LOB_KINDS[@insert.parameters.fetch(index).type.kind]
          bytes = long_octets(value)
          next value unless kind && bytes

          @connection.create_lob(kind).tap { |writer| writer.write(bytes) }.finish
        end
      end

      # The octets of +value+, a string or a large object held whole, if
      # longer than what is sent whole.
      def long_octets(value)
        octets = value.is_a?(Lob) ? value.data : value
        return nil unless octets.is_a?(String) && octets.bytesize > Client::Lobs::INLINE_OCTETS

        octets.b
      end

      # Skips the row and reports it, if the import skips bad rows; else
      # stops.
      def reject(position, failure, input)
        raise stop(position, failure, input) unless @options.skip

        @skipped += 1
        @rejected.call(Rejected.new(position:, failure:, input:))
      end

      # Stops the import at +position+: the batch under way rolled back.
      def stop(position, failure, input)
        if !@connection.lost? && @connection.in_transaction?
          begin
            @connection.query("ROLLBACK")
          rescue Error
            nil
          end
        end
        ImportError.new(failure, position:, committed: @committed, rolled_back: @in_batch, input:)
      end

      # Commits the batch under way, if a transaction is active.
      def commit
        if @connection.in_transaction?
          begin
            @connection.query("COMMIT")
          rescue Error => e
            raise ImportError.new(Import.sql(e), position: nil, committed: @committed, rolled_back: @in_batch,
                                                 input: false)
          end
        end
        @committed += @in_batch
        @in_batch = 0
      end
    end
  end
end
