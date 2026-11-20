# frozen_string_literal: true

require "test_helper"

module Turborel
  module Protocol
    # The composite fields.
    class FieldsTest < Minitest::Test
      include TestSupport

      # Verifies: [PROTOCOL Composite fields] a column is the named flag, its
      # name if named, its data type and the not null flag.
      def test_column
        assert_equal Column.new(name: "A", type: DataType.new(kind: :boolean, params: {}), not_null: false),
                     Fields.column(reader(writer.flag(true).str("A").u8(14).flag(false).to_s))
        assert_fails { Fields.column(reader(hex("02"))) }
      end

      # Verifies: [PROTOCOL Composite fields] a parameter is the varying flag,
      # then its data type, written all the same.
      def test_parameter
        assert_equal Parameter.new(varying: false, type: DataType.new(kind: :uuid, params: {})),
                     Fields.parameter(reader(hex("00 1B")))
      end

      # Verifies: [PROTOCOL Composite fields] a failure is SQLCODE as u32,
      # SQLSTATE, message, cited flag and rule, placed flag and position,
      # active flag, then tail 7 to 15 to the end.
      def test_failure_and_its_diagnostics
        tags = (7..15).flat_map { |tag| [tag, "f#{tag}"] }
        body = writer.u32(0xFFFF_FC69).str("08006").str("m").flag(false).flag(false).flag(false)
        tags.each_slice(2) { |tag, text| body.u8(tag).str(text) }
        failure = Fields.failure(reader(body.to_s))

        assert_equal(-919, failure.sqlcode)
        expected = Diagnostics.new(severity: "f7", detail: "f8", hint: "f9", context: "f10", schema: "f11",
                                   table: "f12", column: "f13", data_type: "f14", constraint: "f15")

        assert_equal expected, failure.diagnostics
        assert_fails do
          Fields.failure(reader(writer.u32(0).str("0").str("m").flag(false).flag(false).flag(false).u8(16).to_s))
        end
      end
    end
  end
end
