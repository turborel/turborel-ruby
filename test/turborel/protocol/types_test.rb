# frozen_string_literal: true

require "test_helper"

module Turborel
  module Protocol
    # Data types as the server writes them.
    class TypesTest < Minitest::Test
      include TestSupport

      def type(bytes) = Types.read(reader(bytes))

      # Verifies: [PROTOCOL Data types] tags 1 and 5, CHARACTER and CHARACTER
      # VARYING, are a length u32 and units u8, 0 characters and 1 octets.
      def test_character_types
        assert_equal DataType.new(kind: :character, params: { length: 10, units: :characters }),
                     type(hex("01 0A000000 00"))
        assert_equal DataType.new(kind: :varying, params: { length: 3, units: :octets }), type(hex("05 03000000 01"))
        assert_fails { type(hex("01 0A000000 02")) }
      end

      # Verifies: [PROTOCOL Data types] tags 2, 3 and 15, the numbers: exact
      # of precision and scale, approximate and DECFLOAT of precision.
      def test_number_types
        assert_equal({ precision: 9, scale: 2 }, type(hex("02 09000000 02000000")).params)
        assert_equal DataType.new(kind: :approximate, params: { precision: 53 }), type(hex("03 35000000"))
        assert_equal DataType.new(kind: :decfloat, params: { precision: 34 }), type(hex("0F 22000000"))
      end

      # Verifies: [PROTOCOL Data types] tags 6 and 7, BINARY and BINARY
      # VARYING, a length u32; 18 and 19, CLOB and BLOB, a length u64 and
      # units.
      def test_binary_and_large_object_types
        assert_equal DataType.new(kind: :binary, params: { length: 4 }), type(hex("06 04000000"))
        assert_equal DataType.new(kind: :varbinary, params: { length: 8 }), type(hex("07 08000000"))
        assert_equal({ length: 2**40, units: :characters }, type(hex("12 0000000000010000 00")).params)
        assert_equal :blob, type(hex("13 FFFFFFFFFFFFFFFF 01")).kind
      end

      # Verifies: [PROTOCOL Data types] tags 8 to 12, DATE, TIME, TIME WITH
      # TIME ZONE, TIMESTAMP and TIMESTAMP WITH TIME ZONE, each a precision.
      def test_datetime_types
        kinds = (8..12).map { |tag| type(writer.u8(tag).u32(6).to_s) }

        assert_equal %i[date time time_zoned timestamp timestamp_zoned], kinds.map(&:kind)
        assert(kinds.all? { |kind| kind.params == { precision: 6 } })
      end

      # Verifies: [PROTOCOL Data types] tag 13, INTERVAL: start field, end
      # field, leading precision, fractional precision, the fields numbered 0
      # YEAR to 5 SECOND.
      def test_interval_type_and_its_fields
        assert_equal({ start: :year, finish: :month, leading: 4, fraction: 0 },
                     type(hex("0D 00000000 01000000 04000000 00000000")).params)
        assert_equal({ start: :day, finish: :second, leading: 2, fraction: 6 },
                     type(hex("0D 02000000 05000000 02000000 06000000")).params)
        assert_fails { type(hex("0D 06000000 05000000 02000000 06000000")) }
      end

      # Verifies: [PROTOCOL Data types] tags 14, 25 and 27, BOOLEAN, JSON
      # and UUID, write nothing after the tag.
      def test_types_with_no_parameters
        assert_equal [DataType.new(kind: :boolean, params: {}), DataType.new(kind: :json, params: {}),
                      DataType.new(kind: :uuid, params: {})], [type(hex("0E")), type(hex("19")), type(hex("1B"))]
      end

      # Verifies: [PROTOCOL Data types] tag 16, an array: its maximum
      # cardinality, 1 to 65535, then its element type, nested; 22, a
      # multiset, its element type.
      def test_array_and_multiset_types
        array = type(hex("10 05000000 10 FFFF0000 0E"))

        assert_equal 5, array.params[:max]
        boolean = DataType.new(kind: :boolean, params: {})

        assert_equal DataType.new(kind: :array, params: { max: 65_535, element: boolean }),
                     array.params[:element]
        assert_equal DataType.new(kind: :multiset, params: { element: DataType.new(kind: :json, params: {}) }),
                     type(hex("16 19"))
        assert_fails { type(hex("10 00000000 0E")) }
        assert_fails { type(hex("10 00000100 0E")) }
      end

      # Verifies: [PROTOCOL Data types] tag 17, a row: a list of each field's
      # name and type, one or more.
      def test_row_type
        row = type(writer.u8(17).u32(2).str("A").u8(14).str("B").u8(25).to_s)

        assert_equal [["A", DataType.new(kind: :boolean, params: {})], ["B", DataType.new(kind: :json, params: {})]],
                     row.params[:fields]
        assert_fails { type(hex("11 00000000")) }
      end

      # Verifies: [PROTOCOL Data types] tags 23 and 24: a structured type's
      # schema and name and its proper supertypes; a reference type's
      # referenced names, then scoped u8 and the scope.
      def test_structured_and_reference_types
        structured = type(writer.u8(23).str("S").str("T").u32(1).str("S").str("BASE").to_s)

        assert_equal({ schema: "S", name: "T", supertypes: [%w[S BASE]] }, structured.params)
        unscoped = type(writer.u8(24).str("S").str("T").u32(0).u8(0).to_s)
        scoped = type(writer.u8(24).str("S").str("T").u32(0).u8(1).str("S").str("TAB").to_s)

        assert_nil unscoped.params[:scope]
        assert_equal %w[S TAB], scoped.params[:scope]
        assert_fails { type(writer.u8(24).str("S").str("T").u32(0).u8(2).to_s) }
      end

      # Verifies: [PROTOCOL Data types] tag 26, XML: primary and secondary
      # modifiers, and of XMLSCHEMA the schema's schema and name, its
      # namespace and its element, each 0 for none or 1 and a string.
      def test_xml_type_and_its_modifiers
        assert_equal({ primary: :document, secondary: :untyped, schema: nil }, type(hex("1A 00 00")).params)
        assert_equal({ primary: :content, secondary: :any, schema: nil }, type(hex("1A 01 01")).params)
        typed = type(writer.u8(26).u8(0).u8(2).str("S").str("X").u8(1).str("urn:x").u8(0).to_s)

        assert_equal({ schema: "S", name: "X", namespace: "urn:x", element: nil }, typed.params[:schema])
        assert_equal :sequence, type(hex("1A 02 00")).params[:primary]
        assert_fails { type(hex("1A 02 01")) }
        assert_fails { type(hex("1A 03 00")) }
        assert_fails { type(hex("1A 00 03")) }
      end

      # Verifies: [PROTOCOL Data types] tag 4, a plug-in's type: its name,
      # its parameters, a list of u32, read by its name whether or not the
      # client has the type.
      def test_plugin_type_is_read_by_its_name
        assert_equal DataType.new(kind: :extension, params: { name: "GEOMETRY", params: [4326] }),
                     type(writer.u8(4).str("GEOMETRY").u32(1).u32(4326).to_s)
        assert_fails { type(writer.u8(4).str("X").u32(3).u32(1).u32(2).u32(3).to_s) }
        assert_fails { type(writer.u8(4).str("X").u32(1).u32(0xFFFF_FFFF).to_s) }
      end

      # Verifies: [PROTOCOL Data types] a distinct type is written as its
      # source type, so it is read as that type; a tag no type has fails
      # the connection.
      def test_distinct_type_reads_as_its_source_and_unknown_tags_fail
        assert_equal :exact, type(hex("02 0A000000 00000000")).kind
        [0, 20, 21, 28, 255].each { |tag| assert_fails { type(writer.u8(tag).to_s) } }
        assert_equal 27, Types.tag(:uuid)
      end

      # Verifies: [DESIGN] D1 types nest at most 16 deep, arrays, multisets
      # and rows alike.
      def test_type_nesting_is_bounded
        deep = writer.tap { |w| 16.times { w.u8(22) } }.u8(14).to_s
        too_deep = writer.tap { |w| 17.times { w.u8(22) } }.u8(14).to_s

        assert_equal :multiset, type(deep).kind
        assert_fails { type(too_deep) }
      end
    end
  end
end
