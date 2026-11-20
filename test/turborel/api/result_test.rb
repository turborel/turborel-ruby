# frozen_string_literal: true

require "test_helper"

module Turborel
  # The plain API's results, made of the low-level client's outcomes.
  class ResultTest < Minitest::Test
    include TestSupport

    COLUMNS = [Column.new(name: "ID", type: nil, not_null: true), Column.new(name: "NAME", type: nil, not_null: false)]
              .freeze

    def query = Result.new(Client::Rows.new(columns: COLUMNS, rows: [[1, "a"], [2, nil]]))

    def completion(rows: 3, sqlstate: "00000")
      Result.new(Client::Completion.new(sqlcode: 0, sqlstate:, active: false, position: nil, more: false, rows:,
                                        generated: [], conditions: [], time: nil))
    end

    # Verifies: [DESIGN] D2 a query's Result: its columns, its rows by row
    # and by column, each value as Appendix A maps it, in order; a row as a
    # Hash of its columns' names; its count.
    def test_a_query
      result = query

      assert_equal [%w[ID NAME], 2, 2, 2, "00000", nil], [result.fields, result.ntuples, result.nfields,
                                                          result.cmd_tuples, result.sqlstate, result.completion]
      assert_equal [{ "ID" => 1, "NAME" => "a" }, { "ID" => 2, "NAME" => nil }], result.to_a
      assert_equal [{ "ID" => 2, "NAME" => nil }, nil], [result[1], result[2]]
      assert_equal [[1, "a"], [2, nil]], result.values
      assert_equal ["a", [1, 2], ["a", nil]],
                   [result.getvalue(0, 1), result.column_values(0), result.field_values("NAME")]
      assert_equal 2, result.each.size
      assert_equal "#<Turborel::Result 2 rows of [\"ID\", \"NAME\"]>", result.inspect
    end

    # Verifies: [DESIGN] D2 another statement's Result: no columns and no
    # rows, its completion's SQLSTATE and the rows it counted.
    def test_a_completion
      result = completion(rows: 4, sqlstate: "02000")

      assert_equal [[], [], 0, 4, "02000"], [result.fields, result.values, result.ntuples, result.cmd_tuples,
                                             result.sqlstate]
      assert_same(result, result.each { flunk })
      assert_equal "#<Turborel::Result sqlstate=02000>", result.inspect
    end

    # Verifies: [DESIGN] D2 a row, a column or a name a result lacks refused
    # with the driver's error, as a misuse.
    def test_what_a_result_lacks
      result = query

      assert_fails(MISUSED) { result.getvalue(2, 0) }
      assert_fails(MISUSED) { result.getvalue(0, 2) }
      assert_fails(MISUSED) { result.column_values(-1) }
      assert_fails(MISUSED) { result.field_values("AGE") }
    end

    # Verifies: [DESIGN] D2 a column of no declared type named and written
    # as its data type's tag says; one declared, as it was declared.
    def test_types_by_their_tags
      exact = Column.new(name: "N", type: DataType.new(kind: :exact, params: { precision: 10, scale: 0 }),
                         not_null: true)
      told = exact.with(declared: Declared.new(name: "INTEGER", written: "INTEGER"))
      result = Result.new(Client::Rows.new(columns: [exact, told], rows: []))

      assert_equal [%w[NUMERIC INTEGER], "NUMERIC(10,0)", "INTEGER"],
                   [result.ftypes, result.type_written(0), result.type_written(1)]
    end
  end
end
