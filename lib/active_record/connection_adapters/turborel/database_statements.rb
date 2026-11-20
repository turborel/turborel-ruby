# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    # The Turborel adapter's parts (RULES.md D2).
    module Turborel
      # Statements run on the driver's connection (RULES.md D2): a
      # statement with no bound values by Query, one with them prepared,
      # kept in the statement pool if ActiveRecord asks, and executed; a
      # transaction begun by autocommit turned off, as Turborel's
      # transactions begin with a statement.
      module DatabaseStatements
        # The statements that read, or that end or mark a transaction.
        READ_QUERY = AbstractAdapter.build_read_query_regexp(
          :begin, :commit, :explain, :select, :set, :release, :savepoint, :rollback, :values, :with
        )
        private_constant :READ_QUERY

        # The isolation levels, as SET TRANSACTION writes them.
        ISOLATION_LEVELS = {
          read_uncommitted: "READ UNCOMMITTED", read_committed: "READ COMMITTED",
          repeatable_read: "REPEATABLE READ", serializable: "SERIALIZABLE"
        }.freeze

        # Whether +sql+ may write.
        #
        # @param sql [String]
        # @return [Boolean]
        def write_query?(sql)
          !READ_QUERY.match?(sql)
        rescue ArgumentError
          !READ_QUERY.match?(sql.b)
        end

        # Begins a transaction: autocommit off, so the next statement begins
        # one.
        #
        # @return [void]
        def begin_db_transaction
          with_raw_connection(allow_retry: true, materialize_transactions: false) do |connection|
            connection.autocommit = false
          end
        end

        # Begins a transaction of +isolation+.
        #
        # @param isolation [Symbol]
        # @return [void]
        def begin_isolated_db_transaction(isolation)
          level = ISOLATION_LEVELS.fetch(isolation) do
            raise TransactionIsolationError, "invalid isolation level: #{isolation.inspect}"
          end
          begin_db_transaction
          internal_execute("SET TRANSACTION ISOLATION LEVEL #{level}", "TRANSACTION", allow_retry: true,
                                                                                      materialize_transactions: false)
        end

        # Commits the transaction, autocommit put back on.
        #
        # @return [void]
        def commit_db_transaction
          internal_execute("COMMIT", "TRANSACTION", allow_retry: false, materialize_transactions: true)
        ensure
          autocommit_again
        end

        # Rolls the transaction back, autocommit put back on.
        #
        # @return [void]
        def exec_rollback_db_transaction
          internal_execute("ROLLBACK", "TRANSACTION", allow_retry: false, materialize_transactions: true)
        ensure
          autocommit_again
        end

        # Runs +sql+, an INSERT: the driver's result, which carries the
        # identity values it generated.
        #
        # @return [::Turborel::Result]
        def exec_insert(sql, name = nil, binds = [], *, **) = internal_execute(sql, name, binds)

        # The rows affected by an INSERT of every row of +sql+.
        #
        # @return [ActiveRecord::Result]
        def exec_insert_all(sql, name) = internal_exec_query(sql, name)

        private

        # Autocommit on again, on a connection still there.
        def autocommit_again
          connection = @raw_connection
          connection.autocommit = true if connection && !connection.finished?
        end

        # Runs +sql+ with +type_casted_binds+, one for each ? mark: a
        # ::Turborel::Result.
        def perform_query(raw_connection, sql, binds, type_casted_binds, **options)
          notification_payload = options.fetch(:notification_payload)
          result = if binds.nil? || binds.empty?
                     raw_connection.exec(sql)
                   elsif options[:prepare]
                     ::Turborel::Result.new(raw_connection.client.execute(pooled(raw_connection, sql),
                                                                          type_casted_binds))
                   else
                     raw_connection.exec_params(sql, type_casted_binds)
                   end
          verified!
          notification_payload[:affected_rows] = result.cmd_tuples
          notification_payload[:row_count] = result.ntuples
          result
        end

        # The statement +sql+ prepared, kept in the statement pool.
        def pooled(raw_connection, sql)
          @statements[sql] ||= raw_connection.client.prepare(sql)
        end

        # +result+ as ActiveRecord's, each value read as Values reads it.
        def cast_result(result)
          return ActiveRecord::Result.empty(affected_rows: result.cmd_tuples) if result.completion

          client = @raw_connection.client
          rows = result.values.map { |row| row.map { |value| Values.read(value, client) } }
          ActiveRecord::Result.new(result.fields.map(&:to_s), rows, affected_rows: result.cmd_tuples)
        end

        # The rows +result+'s statement affected.
        def affected_rows(result) = result.cmd_tuples

        # The first identity value the INSERT of +result+ generated, an
        # Integer if it is one.
        def last_inserted_id(result) = returning_column_values(result).first

        # The identity values the INSERT of +result+ generated, each an
        # Integer, as an identity column is of an exact type of scale 0.
        def returning_column_values(result)
          completion = result.completion
          completion ? completion.generated.map { |text| Integer(text, 10) } : []
        end
      end
    end
  end
end
