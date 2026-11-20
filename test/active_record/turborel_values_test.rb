# frozen_string_literal: true

require "test_helper"

require "active_record/connection_adapters/turborel_adapter"

module ActiveRecord
  module ConnectionAdapters
    module Turborel
      # What the adapter reads and writes, and how it names the driver's
      # failures, with no server.
      class ValuesTest < Minitest::Test
        include ::Turborel::TestSupport

        def datetime(moment, utc, zone: 0, zoned: false, precision: 6)
          ::Turborel::Datetime.new(moment:, utc:, zone:, zoned:, precision:)
        end

        # A client that reads a large object by its locator.
        class Reader
          def lob_reader(_lob) = StringIO.new("by locator".b)
        end

        # Verifies: [DESIGN] D2 a row's values read as ActiveRecord's types
        # cast them: a datetime, a JSON value and the rest as Turborel shows
        # them; a large object's data, by locator read through the client; a
        # Ruby value as it is.
        def test_values_read
          at = datetime(:timestamp, ((Values::EPOCH_SECONDS + 86_400) * Values::MICROSECONDS) + 5)
          read = ->(value) { Values.read(value, Reader.new) }

          assert_equal ["1970-01-02 00:00:00.000005", "01:00:00.000000"],
                       [read.call(at), read.call(datetime(:time, 3_600 * Values::MICROSECONDS))]
          assert_equal ["{\"a\":1}", "1.5", 7, nil, true],
                       [read.call(::Turborel::Json.new(value: { "a" => 1 })), read.call(BigDecimal("1.5")).to_s("F"),
                        read.call(7), read.call(nil), read.call(true)]
          character = ::Turborel::Lob.new(kind: :character, data: nil, locator: 1, octets: 10, characters: 10)
          binary = ::Turborel::Lob.new(kind: :binary, data: "\x00".b, locator: nil, octets: 1, characters: nil)

          assert_equal([["by locator", Encoding::UTF_8], ["\x00".b, Encoding::BINARY]],
                       [read.call(character), read.call(binary)].map { [_1, _1.encoding] })
        end

        # Verifies: [DESIGN] D2 a Ruby datetime written as Turborel's: a
        # timestamp's wall clock in the default time zone, a date its
        # midnight, a time of day its microseconds.
        def test_values_written
          time = Time.utc(1970, 1, 2, 0, 0, 0, 5)
          local = Time.new(1970, 1, 2, 2, 0, 0, "+02:00")

          assert_equal datetime(:timestamp, ((Values::EPOCH_SECONDS + 86_400) * Values::MICROSECONDS) + 5),
                       Values.timestamp(time, :utc)
          assert_equal Values.timestamp(Time.utc(1970, 1, 2), :utc), Values.timestamp(local, :utc)
          assert_equal (local.getlocal.utc_offset + 86_400) * Values::MICROSECONDS,
                       Values.timestamp(local, :local).utc - (Values::EPOCH_SECONDS * Values::MICROSECONDS)
          assert_equal datetime(:date, Values::DAY, precision: 0), Values.date(Date.new(1, 1, 2, Date::GREGORIAN))
          assert_equal datetime(:time, (3_661 * Values::MICROSECONDS) + 7),
                       Values.time(Time.utc(2000, 1, 1, 1, 1, 1, 7))
        end

        # Verifies: [DESIGN] D2 a column's SQL type as declared, its length,
        # precision and scale after it; a default as written read as its
        # value, an expression as none; a referential action by its name.
        def test_defaults
          field = ->(type, **more) { { "DATA_TYPE" => type }.merge(more.transform_keys(&:to_s)) }

          assert_equal ["CHARACTER VARYING(9)", "DECIMAL(5,0)", "TIMESTAMP(3)", "DATE", "BIGINT"],
                       [Defaults.sql_type(field.call("CHARACTER VARYING", CHARACTER_MAXIMUM_LENGTH: 9)),
                        Defaults.sql_type(field.call("DECIMAL", NUMERIC_PRECISION: 5)),
                        Defaults.sql_type(field.call("TIMESTAMP", DATETIME_PRECISION: 3)),
                        Defaults.sql_type(field.call("DATE", DATETIME_PRECISION: 0)),
                        Defaults.sql_type(field.call("BIGINT"))]
          assert_equal(["it's", "2024-01-02", "-1.5E3", "TRUE", nil, nil, nil],
                       ["'it''s'", "DATE '2024-01-02'", "-1.5E3", "TRUE", "NULL", nil, "CURRENT_TIMESTAMP"]
                         .map { Defaults.value(_1) })
          assert_equal([:cascade, :nullify, :restrict, nil],
                       ["CASCADE", "SET NULL", "RESTRICT", "NO ACTION"].map { Defaults.action(_1) })
        end

        # Verifies: [DESIGN] D2 ActiveRecord's error of each of the driver's
        # failures: a connection's lost, a constraint's by what it names, a
        # value too long or out of range, a serialization failure, a
        # cancelled statement; none of another.
        def test_failures
          kind = ->(code, state, message = "") { Failures.kind(::Turborel::Error.of(code, state, message)) }

          assert_equal [ConnectionFailed, RecordNotUnique, RecordNotUnique, InvalidForeignKey, NotNullViolation],
                       [kind.call(-919, "08006"), kind.call(-201, "23000", "PRIMARY KEY K (id) would be violated"),
                        kind.call(-201, "23000", "UNIQUE U (n) would be violated"),
                        kind.call(-201, "23000", "a row references no row: FOREIGN KEY F"),
                        kind.call(-201, "23000", "column n of T is NOT NULL")]
          assert_equal [ValueTooLong, RangeError, SerializationFailure, TransactionRollbackError, QueryCanceled],
                       [kind.call(-301, "22001"), kind.call(-301, "22003"), kind.call(-911, "40001"),
                        kind.call(-911, "40002"), kind.call(-920, "TB920")]
          assert_nil kind.call(-201, "23000", "CHECK C would be violated")
          assert_nil kind.call(-103, "2A000")
        end

        # Verifies: [DESIGN] D2 a statement dropped from the pool destroyed
        # only on a connection still there; the adapter registered only
        # where ActiveRecord's support is loaded.
        def test_pool_and_registration
          adapter = Object.new.tap { _1.instance_variable_set(:@raw_connection, nil) }
          pool = TurborelAdapter::StatementPool.new(adapter, 1)
          pool["a"] = :first
          pool["b"] = :second

          assert_equal [false, :second], [pool.key?("a"), pool["b"]]
          assert_nil ::Turborel::Registration.register(nil)
          ::Turborel::Registration.register(ActiveSupport)

          assert_equal "ActiveRecord::ConnectionAdapters::TurborelAdapter",
                       ActiveRecord::ConnectionAdapters.instance_variable_get(:@adapters).fetch("turborel").first
        end
      end
    end
  end
end
