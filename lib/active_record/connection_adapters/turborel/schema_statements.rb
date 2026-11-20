# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    # The Turborel adapter's parts (RULES.md D2).
    module Turborel
      # The schema read from Turborel's Information Schema and changed by
      # its statements (RULES.md D2): each ALTER TABLE takes one action, a
      # column or table is dropped RESTRICT unless asked CASCADE, and a
      # unique index is a UNIQUE constraint.
      module SchemaStatements
        # The TABLE_TYPEs of ActiveRecord's kinds of data source: a base
        # table, system-versioned among them; a view; either.
        TABLE_TYPES = {
          "BASE TABLE" => "TABLE_TYPE IN ('BASE TABLE', 'SYSTEM VERSIONED')", "VIEW" => "TABLE_TYPE = 'VIEW'",
          "" => "TABLE_TYPE IN ('BASE TABLE', 'SYSTEM VERSIONED', 'VIEW')"
        }.freeze
        private_constant :TABLE_TYPES

        # The tables and views of the session's schema, or the one of
        # +name+.
        #
        # @return [String]
        def data_source_sql(name = nil, type: nil)
          schema, table = parts(name)
          sql = "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = #{quote(schema)}"
          sql << " AND TABLE_NAME = #{quote(table)}" if table
          sql << " AND #{TABLE_TYPES.fetch(type.to_s, TABLE_TYPES[""])}"
          sql << " ORDER BY TABLE_NAME"
        end

        # The names of the columns of the primary key of +table_name+, in
        # order.
        #
        # @param table_name [String, Symbol]
        # @return [Array<String>]
        def primary_keys(table_name)
          schema, table = parts(table_name)
          query_values(<<~SQL.squish, "SCHEMA")
            SELECT K.COLUMN_NAME FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS C
            JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE K
              ON K.CONSTRAINT_SCHEMA = C.CONSTRAINT_SCHEMA AND K.CONSTRAINT_NAME = C.CONSTRAINT_NAME
            WHERE C.TABLE_SCHEMA = #{quote(schema)} AND C.TABLE_NAME = #{quote(table)}
              AND C.CONSTRAINT_TYPE = 'PRIMARY KEY'
            ORDER BY K.ORDINAL_POSITION
          SQL
        end

        # The indexes of +table_name+: those CREATE INDEX made, then its
        # UNIQUE constraints, each a unique index of its own name.
        #
        # @param table_name [String, Symbol]
        # @return [Array<IndexDefinition>]
        def indexes(table_name)
          schema, table = parts(table_name)
          unique = unique_constraints(schema, table).map do |name, columns|
            IndexDefinition.new(table_name, name, true, columns)
          end
          made_indexes(table_name, schema, table) + unique
        end

        # The foreign keys of +table_name+.
        #
        # @param table_name [String, Symbol]
        # @return [Array<ForeignKeyDefinition>]
        def foreign_keys(table_name)
          schema, table = parts(table_name)
          internal_exec_query(<<~SQL.squish, "SCHEMA").rows.map { |row| foreign_key(table_name, row) }
            SELECT R.CONSTRAINT_NAME, K.COLUMN_NAME, U.TABLE_NAME, U.COLUMN_NAME, R.UPDATE_RULE, R.DELETE_RULE
            FROM INFORMATION_SCHEMA.REFERENTIAL_CONSTRAINTS R
            JOIN INFORMATION_SCHEMA.TABLE_CONSTRAINTS C
              ON C.CONSTRAINT_SCHEMA = R.CONSTRAINT_SCHEMA AND C.CONSTRAINT_NAME = R.CONSTRAINT_NAME
            JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE K
              ON K.CONSTRAINT_SCHEMA = R.CONSTRAINT_SCHEMA AND K.CONSTRAINT_NAME = R.CONSTRAINT_NAME
            JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE U
              ON U.CONSTRAINT_SCHEMA = R.UNIQUE_CONSTRAINT_SCHEMA AND U.CONSTRAINT_NAME = R.UNIQUE_CONSTRAINT_NAME
              AND U.ORDINAL_POSITION = K.ORDINAL_POSITION
            WHERE C.TABLE_SCHEMA = #{quote(schema)} AND C.TABLE_NAME = #{quote(table)}
            ORDER BY R.CONSTRAINT_NAME
          SQL
        end

        # Drops each of +table_names+, RESTRICT, or CASCADE if +force+ is
        # :cascade; one not there passed over if +if_exists+.
        #
        # @return [void]
        def drop_table(*table_names, **options)
          table_names.each do |table_name|
            schema_cache.clear_data_source_cache!(table_name.to_s)
            next if options[:if_exists] && !data_source_exists?(table_name)

            execute "DROP TABLE #{quote_table_name(table_name)} #{behavior(options)}"
          end
        end

        # Drops each of +column_names+ of +table_name+, an ALTER TABLE each.
        #
        # @return [void]
        def remove_columns(table_name, *column_names, type: nil, **options)
          _ = type
          raise ArgumentError, "You must specify at least one column name." if column_names.empty?

          column_names.each do |name|
            execute "ALTER TABLE #{quote_table_name(table_name)} #{remove_column_for_alter(table_name, name,
                                                                                           **options)}"
          end
        end

        # Adds created_at and updated_at to +table_name+, NOT NULL unless
        # asked otherwise, an ALTER TABLE each.
        #
        # @return [void]
        def add_timestamps(table_name, **options)
          options[:null] = false if options[:null].nil?
          options[:precision] = 6 unless options.key?(:precision)
          %i[created_at updated_at].each { |name| add_column(table_name, name, :datetime, **options) }
        end

        # Drops created_at and updated_at of +table_name+.
        #
        # @return [void]
        def remove_timestamps(table_name, **) = remove_columns(table_name, :updated_at, :created_at, **)

        # Renames the column +column_name+ of +table_name+, and the indexes
        # named after it.
        #
        # @return [void]
        def rename_column(table_name, column_name, new_column_name)
          clear_cache!
          execute "ALTER TABLE #{quote_table_name(table_name)} #{rename_column_sql(table_name, column_name,
                                                                                   new_column_name)}"
          rename_column_indexes(table_name, column_name, new_column_name)
        end

        # Sets or drops the default of the column +column_name+.
        #
        # @return [void]
        def change_column_default(table_name, column_name, default_or_changes)
          clear_cache!
          default = extract_new_default_value(default_or_changes)
          action = if default.nil?
                     "DROP DEFAULT"
                   else
                     "SET DEFAULT #{quote_default_expression(default, column_for(table_name, column_name))}"
                   end
          execute "ALTER TABLE #{quote_table_name(table_name)} ALTER COLUMN #{quote_column_name(column_name)} #{action}"
        end

        # Adds an index to +table_name+: a UNIQUE constraint if +unique+,
        # else CREATE INDEX.
        #
        # @return [void]
        def add_index(table_name, column_name, **)
          index, _algorithm, if_not_exists = add_index_options(table_name, column_name, **)
          return if if_not_exists && indexes(table_name).any? { |known| known.name == index.name }

          execute index_sql(index)
        end

        # Renames the index +old_name+ of +table_name+: dropped and made
        # again, as Turborel renames no index.
        #
        # @return [void]
        def rename_index(table_name, old_name, new_name)
          index = indexes(table_name).find { |known| known.name == old_name.to_s }
          raise ArgumentError, "Index name '#{old_name}' on table '#{table_name}' does not exist" unless index

          remove_index(table_name, name: old_name)
          add_index(table_name, index.columns, name: new_name, unique: index.unique, using: index.using)
        end

        # Drops an index of +table_name+, or the UNIQUE constraint it is.
        #
        # @return [void]
        def remove_index(table_name, column_name = nil, **options)
          return if options[:if_exists] && !index_exists?(table_name, column_name, **options)

          name = index_name_for_remove(table_name, column_name, options)
          unique = indexes(table_name).find { |index| index.name == name }&.unique
          execute(if unique
                    "ALTER TABLE #{quote_table_name(table_name)} DROP CONSTRAINT #{quote_column_name(name)} RESTRICT"
                  else
                    "DROP INDEX #{quote_column_name(name)}"
                  end)
        end

        # +type+ as Turborel names it: an integer by its bytes, SMALLINT,
        # INTEGER or BIGINT.
        #
        # @return [String]
        def type_to_sql(type, limit: nil, precision: nil, scale: nil, **)
          return super unless type.to_s == "integer"

          case limit
          when nil, 3, 4 then "INTEGER"
          when 1, 2 then "SMALLINT"
          when 5..8 then "BIGINT"
          else raise ArgumentError, "No integer type has byte size #{limit}. Use a decimal with scale 0 instead."
          end
        end

        # How Turborel's ALTER TABLE and CREATE TABLE are written.
        #
        # @return [SchemaCreation]
        def schema_creation = Turborel::SchemaCreation.new(self)

        private

        # The schema and table of +name+, "schema.table" or a table's alone,
        # in the session's schema.
        def parts(name)
          schema, table = name.to_s.split(".", 2)
          table ? [schema, table] : [current_schema, schema]
        end

        # The session's default schema.
        def current_schema
          with_raw_connection(materialize_transactions: false) { |connection| connection.client.setting("SCHEMA") }
        end

        # The column definitions of +table_name+, from INFORMATION_SCHEMA.
        def column_definitions(table_name)
          schema, table = parts(table_name)
          internal_exec_query(<<~SQL.squish, "SCHEMA").to_a
            SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, NUMERIC_PRECISION, NUMERIC_SCALE,
              DATETIME_PRECISION, IS_NULLABLE, COLUMN_DEFAULT, IS_IDENTITY
            FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = #{quote(schema)} AND TABLE_NAME = #{quote(table)}
            ORDER BY ORDINAL_POSITION
          SQL
        end

        # The Column of +field+, a row of column_definitions.
        def new_column_from_field(_table_name, field, _definitions)
          sql_type = Defaults.sql_type(field)
          default = field["COLUMN_DEFAULT"]
          value = Defaults.value(default)
          Column.new(field["COLUMN_NAME"], lookup_cast_type(sql_type), value, fetch_type_metadata(sql_type),
                     field["IS_NULLABLE"] == "YES", value.nil? && default != "NULL" ? default : nil,
                     identity: field["IS_IDENTITY"] == "YES")
        end

        # The indexes CREATE INDEX made on +table+ in +schema+, a B-tree's
        # method unnamed, as it is the default.
        def made_indexes(table_name, schema, table)
          rows = internal_exec_query(<<~SQL.squish, "SCHEMA").rows
            SELECT INDEX_NAME, COLUMN_NAMES, METHOD_NAME FROM INFORMATION_SCHEMA.INDEXES
            WHERE TABLE_SCHEMA = #{quote(schema)} AND TABLE_NAME = #{quote(table)} AND IS_UNIQUE = 'NO'
            ORDER BY INDEX_NAME
          SQL
          rows.map do |name, columns, method|
            using = method.to_s.downcase
            IndexDefinition.new(table_name, name, false, columns.split(/,\s*/),
                                using: using == "btree" ? nil : using.to_sym)
          end
        end

        # The UNIQUE constraints of +table+ in +schema+, each its name and
        # columns in order.
        def unique_constraints(schema, table)
          rows = internal_exec_query(<<~SQL.squish, "SCHEMA").rows
            SELECT C.CONSTRAINT_NAME, K.COLUMN_NAME FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS C
            JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE K
              ON K.CONSTRAINT_SCHEMA = C.CONSTRAINT_SCHEMA AND K.CONSTRAINT_NAME = C.CONSTRAINT_NAME
            WHERE C.TABLE_SCHEMA = #{quote(schema)} AND C.TABLE_NAME = #{quote(table)} AND C.CONSTRAINT_TYPE = 'UNIQUE'
            ORDER BY C.CONSTRAINT_NAME, K.ORDINAL_POSITION
          SQL
          rows.group_by(&:first).map { |name, columns| [name, columns.map(&:last)] }
        end

        # The ForeignKeyDefinition of a row of foreign_keys.
        def foreign_key(table_name, row)
          name, column, to_table, primary_key, on_update, on_delete = row
          ForeignKeyDefinition.new(table_name, to_table, name:, column:, primary_key:,
                                                         on_update: Defaults.action(on_update),
                                                         on_delete: Defaults.action(on_delete))
        end

        # The statement that makes +index+.
        def index_sql(index)
          columns = index.columns.map { |column| quote_column_name(column) }.join(", ")
          table = quote_table_name(index.table)
          name = quote_column_name(index.name)
          return "ALTER TABLE #{table} ADD CONSTRAINT #{name} UNIQUE (#{columns})" if index.unique

          "CREATE INDEX #{name} ON #{table} (#{columns})#{" USING #{index.using.to_s.upcase}" if index.using}"
        end

        # CASCADE if +options+ ask it, else RESTRICT.
        def behavior(options) = options[:force] == :cascade ? "CASCADE" : "RESTRICT"

        # DROP COLUMN, RESTRICT.
        def remove_column_for_alter(_table_name, column_name, _type = nil, **options)
          "DROP COLUMN #{quote_column_name(column_name)} #{behavior(options)}"
        end
      end
    end
  end
end
