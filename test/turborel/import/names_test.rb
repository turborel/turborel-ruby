# frozen_string_literal: true

require "test_helper"

module Turborel
  module Import
    # SQL names and string assignment as an import makes them.
    class NamesTest < Minitest::Test
      include TestSupport

      def varying(length, units = :characters) = DataType.new(kind: :varying, params: { length:, units: })

      # Verifies: [CLIENT Importing] a table named in any way a <table name>
      # may be, written again as delimited identifiers; anything else
      # refused, saying so.
      def test_table_names
        assert_equal '"X"."STAFF"', Names.table_name("x.staff")
        assert_equal '"X"."STAFF"', Names.table_name("\"X\" . \"STAFF\"")
        assert_equal '"C"."S"."two ""words"""', Names.table_name("c.s.\"two \"\"words\"\"\"")
        ["STAFF; DROP TABLE STAFF", "1STAFF", "A.B.C.D", "X.", "'STAFF'", "", "SELECT", "\"\"", "\"open",
         "\"line\nbreak\"", "a" * 129, "x'01'", "\"#{"a" * 129}\""].each do |wrong|
          refused = assert_raises(SourceError) { Names.table_name(wrong) }

          assert_equal "[ISO/IEC 9075:1992 §5.4] #{wrong} is not a <table name>", refused.message
        end
        assert_equal "\"A#{"_" * 200}B\"", Names.table_name("a#{"_" * 200}b"), "underscores are not counted"
      end

      # Verifies: [CLIENT Importing] a heading names the column of its
      # identifier, a regular one in upper case and so a key word, else its
      # name as written.
      def test_column_names
        assert_equal(["ID", "VALUE", "Mixed", "two words", "a.b", "1x"],
                     ["id", "value", "\"Mixed\"", "two words", "a.b", "1x"].map { Names.column_name(_1) })
      end

      # Verifies: [CLIENT Importing] a string for a character string column
      # assigned as INSERT assigns: padded of CHARACTER, kept of VARYING, a
      # large object of CLOB; spaces past the length cut; more refused
      # (22001), counted in characters or octets; any other value as it is.
      def test_strings_assigned
        character = DataType.new(kind: :character, params: { length: 3, units: :characters })
        clob = DataType.new(kind: :clob, params: { length: 4, units: :characters })
        parameters = [character, varying(3), clob, varying(3, :octets), DataType.new(kind: :exact, params: {})]
                     .map { Parameter.new(varying: false, type: _1) }
        values = Assign.assigned(["ab", "abc   ", "abc", "é", "toolong"], parameters)

        assert_equal(["ab ", "abc", "abc", "é", "toolong"], values.map { _1.is_a?(Lob) ? _1.data : _1 })
        assert_kind_of Lob, values[2]
        assert_equal "", Assign.prefix("é", 1, true)
        [[["abcd"], character, "§9.2 GR3b ii",
          "a value of 4 characters, not spaces beyond 3, does not fit CHARACTER(3)"],
         [["abcd"], varying(3), "§9.2 GR3e ii",
          "a value of 4 characters, not spaces beyond 3, does not fit CHARACTER VARYING(3)"],
         [["éé"], varying(3, :octets), "§9.2 GR3e ii",
          "a value of 4 octets, not spaces beyond 3, does not fit CHARACTER VARYING(3 OCTETS)"]]
          .each do |value, type, clause, message|
          refused = assert_fails([-301, "22001"]) { Assign.assigned(value, [Parameter.new(varying: false, type:)]) }

          assert_equal ["ISO/IEC 9075:1992 §13.8 GR4b iii, #{clause}", message], [refused.rule, refused.message]
        end
        long = assert_fails([-301, "22001"]) { Assign.assigned(["abcde"], [Parameter.new(varying: false, type: clob)]) }

        assert_equal "ISO/IEC 9075:1992 §13.8 GR4b iii; ISO/IEC 9075-2:2023 §9.2 GR3e ii", long.rule
      end
    end
  end
end
