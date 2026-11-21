# frozen_string_literal: true

require "test_helper"

require "active_record/connection_adapters/turborel_adapter"
require_relative "../server/live_server"

module ActiveRecord
  module ConnectionAdapters
    # The ActiveRecord adapter on a live server (RULES.md R-TEST-8), skipped
    # without one.
    class LiveTurborelAdapterTest < Minitest::Test
      include ::Turborel::TestSupport
      include ::Turborel::LiveServer::Case

      # A model of the tests' own.
      class Author < ActiveRecord::Base
        self.table_name = "ar_authors"
        has_many :books, class_name: "ActiveRecord::ConnectionAdapters::LiveTurborelAdapterTest::Book"
      end

      # Another, which belongs to an author.
      class Book < ActiveRecord::Base
        self.table_name = "ar_books"
        belongs_to :author, class_name: "ActiveRecord::ConnectionAdapters::LiveTurborelAdapterTest::Author"
      end

      def config(**more)
        { adapter: "turborel", host: "127.0.0.1", port: server.port, username: "ann",
          tls_mode: "disable" }.merge(more)
      end

      def setup
        super
        ActiveRecord::Base.establish_connection(config)
        ActiveRecord::Migration.verbose = false
        schema
        connection.schema_cache.clear!
        [Author, Book].each(&:reset_column_information)
      end

      def connection = ActiveRecord::Base.lease_connection

      def schema
        ActiveRecord::Schema.define do
          create_table :ar_authors, force: :cascade do |t|
            t.string :name, null: false
            t.text :bio
            t.boolean :active, default: true
            t.decimal :score, precision: 10, scale: 2
            t.date :born
            t.time :wakes, precision: 6
            t.binary :photo
            t.json :meta
            t.timestamps
          end
          create_table :ar_books, force: :cascade do |t|
            t.references :author, foreign_key: { to_table: :ar_authors }
            t.string :title, limit: 20
            t.integer :pages, limit: 2
            t.bigint :editor_id
            t.index :title, unique: true
          end
        end
      end

      # Verifies: [DESIGN] D2 the adapter registered as turborel, by the
      # gem's own registration too, connecting by settings or a URL; models
      # created, read with each type as ActiveRecord casts it, found,
      # updated and destroyed.
      def test_models
        ActiveRecord::Base.establish_connection(adapter: "turborel",
                                                url: "turborel://ann@127.0.0.1:#{server.port}/?tls_mode=disable")
        ada = Author.create!(name: "Ada", bio: "notes", score: 1.5, born: Date.new(1815, 12, 10), wakes: "07:30:01.5",
                             photo: "\x00\xFF".b, meta: { "k" => [1, 2] })
        read = Author.find(ada.id)

        assert_equal ["Ada", "notes", true, BigDecimal("1.5"), Date.new(1815, 12, 10), "\x00\xFF".b, { "k" => [1, 2] }],
                     [read.name, read.bio, read.active, read.score, read.born, read.photo, read.meta]
        assert_equal ["07:30:01.500000", ada.created_at.floor(6)],
                     [read.wakes.strftime("%H:%M:%S.%6N"), read.created_at]
        read.update!(name: "Ada L")

        assert_equal ["Ada L"], Author.pluck(:name)
        read.destroy!

        assert_equal 0, Author.count
      end

      # Verifies: [DESIGN] D2 associations, where, order, limit and offset
      # written as OFFSET and FETCH FIRST, exists?, counts, a literal of a
      # date written as a typed one; a statement with bound values not
      # prepared; at most statement_limit statements kept prepared.
      def test_queries
        ActiveRecord::Base.establish_connection(config(statement_limit: 2))
        ada = Author.create!(name: "Ada")
        %w[Notes More Last].each_with_index { |title, i| ada.books.create!(title:, pages: i) }

        second = Book.where(author: ada).order(:title).offset(1).limit(1).pluck(:title)

        assert_equal [["More"], 3, true, false],
                     [second, ada.books.count, Book.exists?(title: "Notes"), Book.exists?(title: "x")]
        assert_equal ["Ada"], Author.where('"born" IS NULL OR "born" < ?', Date.new(2000, 1, 1)).pluck(:name)
        assert_equal ["Ada"], Author.where(created_at: ...(Time.now + 60)).pluck(:name)
        binds = [Relation::QueryAttribute.new("n", 2, Type::Integer.new)]

        assert_equal [[2]], connection.exec_query("VALUES CAST(? AS INTEGER)", "SQL", binds, prepare: false).rows
        assert_operator connection.instance_variable_get(:@statements).length, :<=, 2
      end

      # Verifies: [DESIGN] D2 transactions: committed, rolled back, nested
      # by savepoints, of an isolation level, an unknown level refused.
      def test_transactions
        Author.transaction do
          Author.create!(name: "kept")
          Author.transaction(requires_new: true) do
            Author.create!(name: "undone")
            raise ActiveRecord::Rollback
          end
        end
        Author.transaction(isolation: :serializable) do
          Author.create!(name: "rolled back")
          raise ActiveRecord::Rollback
        end

        assert_equal ["kept"], Author.pluck(:name)
        assert_raises(TransactionIsolationError) { connection.begin_isolated_db_transaction(:snapshot) }
        refute_predicate connection.raw_connection, :in_transaction?
      end

      # Verifies: [DESIGN] D2 the driver's failures as ActiveRecord's errors:
      # a key, a foreign key and NOT NULL violated, a literal too long, any
      # other as StatementInvalid.
      def test_errors
        Book.create!(title: "Notes")

        assert_raises(RecordNotUnique) { Book.create!(title: "Notes") }
        assert_raises(InvalidForeignKey) { Book.create!(title: "Orphan", author_id: 999) }
        assert_raises(NotNullViolation) { Author.create!(name: nil) }
        assert_raises(ValueTooLong) { connection.execute(%(INSERT INTO "ar_books" ("title") VALUES ('#{"x" * 30}'))) }
        error = assert_raises(StatementInvalid) { connection.execute("SELECT * FROM nowhere") }

        assert_equal "2A000", error.cause.sqlstate
      end

      # Verifies: [DESIGN] D2 the schema read back: tables, views, columns
      # with their types, nullability and defaults, primary keys, indexes,
      # a UNIQUE constraint's among them, and foreign keys; and dumped.
      def test_schema_read
        connection.execute('CREATE VIEW "ar_names" AS SELECT "name" FROM "ar_authors"')
        columns = Author.columns_hash

        assert_includes connection.tables, "ar_authors"
        assert_equal [["ar_names"], true, false], [connection.views, connection.view_exists?("ar_names"),
                                                   connection.table_exists?("ar_names")]
        assert_equal [:integer, :string, :text, :boolean, "TRUE", :time, true],
                     [columns["id"].type, columns["name"].type, columns["bio"].type, columns["active"].type,
                      columns["active"].default, columns["wakes"].type, columns["id"].auto_incremented_by_db?]
        assert_equal [["id"], [["index_ar_books_on_author_id", false], ["index_ar_books_on_title", true]]],
                     [connection.primary_keys("ar_books"), connection.indexes("ar_books").map { [_1.name, _1.unique] }]
        connection.add_foreign_key(:ar_books, :ar_authors, column: :editor_id, on_delete: :nullify, name: "fk_editor")

        assert_equal [["ar_authors", "author_id", nil], ["ar_authors", "editor_id", :nullify]],
                     connection.foreign_keys("ar_books").map { |key| [key.to_table, key.column, key.on_delete] }.sort
        dumped = StringIO.new
        SchemaDumper.dump(ActiveRecord::Base.connection_pool, dumped)

        assert_match(/create_table "ar_books", force: :cascade do \|t\|\n    t.bigint "author_id"/, dumped.string)
        connection.execute('DROP VIEW "ar_names" CASCADE')
      end

      # Verifies: [DESIGN] D2 the schema changed: columns added, renamed,
      # given a default and dropped, an ALTER TABLE each; timestamps added
      # and removed; indexes, unique and not, made and dropped; a foreign key
      # dropped; tables dropped RESTRICT, CASCADE or if they exist; integer
      # types by their bytes.
      def test_schema_changed
        connection.add_column :ar_books, :isbn, :string, limit: 13, default: "it's"
        connection.rename_column :ar_books, :title, :heading
        connection.change_column_default :ar_books, :pages, from: nil, to: 7
        connection.change_column_default :ar_books, :pages, nil
        connection.add_timestamps :ar_books, null: true
        connection.add_index :ar_books, :isbn, using: :hash
        connection.add_index :ar_books, :isbn, using: :hash, if_not_exists: true
        connection.add_index :ar_books, %i[isbn pages], unique: true
        Book.reset_column_information

        assert_equal ["it's", nil, true], [Book.columns_hash["isbn"].default, Book.columns_hash["pages"].default,
                                           Book.column_names.include?("heading")]
        assert_equal %w[index_ar_books_on_author_id index_ar_books_on_heading index_ar_books_on_isbn
                        index_ar_books_on_isbn_and_pages], connection.indexes(:ar_books).map(&:name).sort
        schema_undone
      end

      # Verifies: [DESIGN] D2 the connection: active by a Ping, its server's
      # version, disconnected, reconnected, discarded.
      def test_the_connection
        assert_predicate connection, :active?
        assert_kind_of AbstractAdapter::Version, connection.database_version
        connection.reconnect!
        connection.raw_connection.client.instance_variable_get(:@stream).close

        refute_predicate connection, :active?
        connection.disconnect!

        refute_predicate connection, :active?
        connection.reconnect!

        assert_equal [[1]], connection.exec_query("VALUES 1").rows
        connection.raw_connection.client.abandon

        refute_predicate connection, :active?
        connection.reconnect!
        connection.discard!
        connection.discard!
      end

      # Verifies: [DESIGN] D2 connecting: by a URL alone; a user refused, a
      # server not reached, as ActiveRecord's errors; whether a database can
      # be reached.
      def test_connecting
        ActiveRecord::Base.establish_connection(config(port: 1))
        assert_raises(ConnectionNotEstablished) { ActiveRecord::Base.lease_connection.execute("VALUES 1") }
        assert_equal "ANN", TurborelAdapter.new_client(url: "turborel://ann@127.0.0.1:#{server.port}/?tls_mode=disable")
                                           .tap(&:close).client.authorization

        assert_raises(DatabaseConnectionError) { TurborelAdapter.new_client(config(password: "secret")) }
        assert_raises(ConnectionNotEstablished) { TurborelAdapter.new_client(config(port: 1)) }
        assert_equal [true, false], [TurborelAdapter.database_exists?(config),
                                     TurborelAdapter.database_exists?(config(port: 1))]
      end

      # Verifies: [DESIGN] D2 SQL as Turborel reads it: names in double
      # quotes, a string's quote doubled and no other character escaped,
      # datetimes typed, binary strings in hexadecimal; whether a statement
      # may write.
      def test_quoting
        assert_equal ['"a""b"', '"s"."t"', "'it''s \\'"],
                     [connection.quote_column_name('a"b'), connection.quote_table_name("s.t"),
                      connection.quote("it's \\")]
        assert_equal ["DATE '2024-01-02'", "TIMESTAMP '2024-01-02 03:04:05.000006'", "X'00ff'"],
                     [connection.quote(Date.new(2024, 1, 2)), connection.quote(Time.utc(2024, 1, 2, 3, 4, 5, 6)),
                      connection.quote(Type::Binary::Data.new("\x00\xff".b))]
        assert_equal [[[Date.new(2024, 1, 2)]], "TIME '03:04:05'"],
                     [connection.select_rows("VALUES #{connection.quote(Date.new(2024, 1, 2))}")
                                .map { |row| row.map { Date.parse(_1) } },
                      connection.quote(Type::Time.new.serialize("03:04:05"))]
        assert_equal [false, true, true],
                     [connection.write_query?("SELECT 1"), connection.write_query?("DELETE FROM t"),
                      connection.write_query?("DELETE \xff".b.force_encoding("UTF-8"))]
      end

      # Verifies: [DESIGN] D2 the adapter's edges: a statement with no rows
      # as an empty result, the identity values of none, a table named with
      # its schema, a decimal's type by its scale.
      def test_edges
        assert_equal [[], []], [connection.exec_query('DELETE FROM "ar_books"').rows,
                                connection.send(:returning_column_values, connection.exec_insert("VALUES 1"))]
        assert_equal %w[id author_id title pages editor_id], connection.columns("ANN.ar_books").map(&:name)
        assert_equal([Type::DecimalWithoutScale, Type::Decimal, Type::DecimalWithoutScale],
                     ["DECIMAL", "DECIMAL(10,2)", "NUMERIC(5,0)"].map { connection.lookup_cast_type(_1).class })
      end

      # Verifies: [DESIGN] D2 more of the schema's edges: an index renamed
      # or one not there, timestamps' defaults; a failure no driver's error;
      # a transaction whose connection is lost.
      def test_more_edges
        connection.rename_index :ar_books, "index_ar_books_on_title", "index_ar_books_titled"
        assert_raises(ArgumentError) { connection.rename_index :ar_books, "nowhere", "anywhere" }
        assert_raises(StatementInvalid) { connection.remove_index :ar_books, name: "nowhere" }
        connection.add_timestamps :ar_books, precision: 3
        created = connection.columns(:ar_books).find { _1.name == "created_at" }

        assert_equal [false, 3], [created.null, created.precision]
        translated = connection.send(:translate_exception, ArgumentError.new("x"), message: "x", sql: "", binds: [])

        assert_instance_of StatementInvalid, translated
        lost_transaction
      end

      # Verifies: [DESIGN] D2 a column's type changed by SET DATA TYPE, with
      # its default and nullability; NOT NULL set, its nulls given a value
      # first, and dropped; a table renamed by RENAME TO, its indexes named
      # after it renamed too.
      def test_columns_and_tables_changed
        Book.create!(title: "Notes")
        connection.change_column :ar_books, :title, :string, limit: 40
        connection.change_column :ar_books, :pages, :integer, limit: 4, default: 3, null: true
        connection.change_column_null :ar_books, :editor_id, false, 0
        connection.change_column_null :ar_books, :pages, true
        columns = connection.columns(:ar_books).to_h { [_1.name, _1] }

        assert_equal ["CHARACTER VARYING(40)", "INTEGER", "3", false, true],
                     [columns["title"].sql_type, columns["pages"].sql_type, columns["pages"].default,
                      columns["editor_id"].null, columns["pages"].null]
        assert_equal [[0]], connection.select_rows('SELECT "editor_id" FROM "ar_books"')
        connection.rename_table :ar_books, :ar_volumes

        assert_equal [false, true], [connection.table_exists?(:ar_books), connection.table_exists?(:ar_volumes)]
        assert_includes connection.indexes(:ar_volumes).map(&:name), "index_ar_volumes_on_title"
        connection.rename_table :ar_volumes, :ar_books, _uses_legacy_table_name: true
      end

      # Verifies: [DESIGN] D2 a result's column types those the server
      # declared, INTEGER an integer, a DECIMAL of a scale a decimal.
      def test_result_column_types
        connection.execute('CREATE TABLE "ar_typed" ("i" INTEGER, "n" NUMERIC(10,0), "d" DECIMAL(9,2))')
        types = connection.select_all('SELECT "i", "n", "d" FROM "ar_typed"').column_types

        assert_equal([Type::Integer, Type::DecimalWithoutScale, Type::Decimal], %w[i n d].map { types.fetch(_1).class })
        connection.drop_table :ar_typed
      end

      # Verifies: [DESIGN] D2 a decimal column of 38 digits, Turborel's most,
      # made, read back as declared and holding a value of 38 digits exactly.
      def test_decimals_of_38_digits
        connection.create_table(:ar_wide, force: true) { |t| t.decimal :amount, precision: 38, scale: 10 }
        wide = Class.new(ActiveRecord::Base) { self.table_name = "ar_wide" }
        amount = BigDecimal("1234567890123456789012345678.9012345678")
        wide.create!(amount:)

        assert_equal [38, 10, amount], [wide.columns_hash["amount"].precision, wide.columns_hash["amount"].scale,
                                        wide.first.amount]
        connection.drop_table :ar_wide
      end

      private

      # What test_schema_changed made, undone.
      def schema_undone
        connection.remove_index :ar_books, :isbn
        connection.remove_index :ar_books, %i[isbn pages]
        connection.remove_index :ar_books, :isbn, if_exists: true
        connection.remove_timestamps :ar_books
        connection.remove_columns :ar_books, :isbn
        connection.remove_foreign_key :ar_books, :ar_authors
        assert_raises(ArgumentError) { connection.remove_columns :ar_books }
        assert_equal [[], %w[id author_id heading pages editor_id]], [connection.foreign_keys(:ar_books),
                                                                      connection.columns(:ar_books).map(&:name)]
        connection.drop_table :ar_books
        connection.drop_table :ar_nothing, if_exists: true
        connection.drop_table :ar_authors, force: :cascade

        assert_equal(%w[SMALLINT INTEGER BIGINT], [2, nil, 8].map { connection.type_to_sql(:integer, limit: _1) })
        assert_raises(ArgumentError) { connection.type_to_sql(:integer, limit: 16) }
      end

      # A transaction whose connection is lost, its rollback failing, the
      # block's exception raised.
      def lost_transaction
        assert_raises(ArgumentError) do
          Author.transaction do
            Author.create!(name: "lost")
            connection.raw_connection.client.abandon
            raise ArgumentError
          end
        end
        connection.reconnect!

        assert_equal 0, Author.count
      end
    end
  end
end
