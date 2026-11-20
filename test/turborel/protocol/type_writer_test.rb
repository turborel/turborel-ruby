# frozen_string_literal: true

require "test_helper"

module Turborel
  module Protocol
    # Data types written as the server writes them.
    class TypeWriterTest < Minitest::Test
      include TestSupport

      def type(kind, **params) = DataType.new(kind:, params:)

      def round_trip(type)
        writer = Writer.new
        TypeWriter.write(writer, type)
        reader = Reader.new(writer.to_s, "type")
        Types.read(reader).tap { reader.finish }
      end

      # Every kind of data type, read back as it was written.
      def every_type
        integer = type(:exact, precision: 10, scale: 0)
        [type(:character, length: 10, units: :characters), type(:varying, length: 3, units: :octets), integer,
         type(:approximate, precision: 53), type(:decfloat, precision: 34), type(:binary, length: 4),
         type(:varbinary, length: 9), type(:date, precision: 0), type(:time, precision: 6),
         type(:time_zoned, precision: 0), type(:timestamp, precision: 3), type(:timestamp_zoned, precision: 6),
         type(:interval, start: :day, finish: :second, leading: 2, fraction: 6), type(:boolean),
         type(:clob, length: 1 << 40, units: :characters), type(:blob, length: 10, units: :octets),
         type(:array, max: 5, element: integer), type(:multiset, element: integer),
         type(:row, fields: [["A", integer], ["B", type(:boolean)]]),
         type(:structured, schema: "S", name: "T", supertypes: [%w[S U]]),
         type(:reference, schema: "S", name: "T", supertypes: [], scope: %w[S TAB]),
         type(:reference, schema: "S", name: "T", supertypes: [], scope: nil), type(:json), type(:uuid),
         type(:xml, primary: :content, secondary: :untyped, schema: nil),
         type(:xml, primary: :document, secondary: :xmlschema,
                    schema: { schema: "S", name: "X", namespace: "urn:x", element: nil }),
         type(:extension, name: "ST_GEOMETRY", params: [4326])]
      end

      # Verifies: [PROTOCOL Data types] each data type written as the server
      # writes it, tag and parameters, reads back as it was; a column its
      # named flag, name, type and not null flag.
      def test_every_type_round_trips
        every_type.each { |t| assert_equal t, round_trip(t) }
        writer = Writer.new
        TypeWriter.column(writer, Column.new(name: nil, type: type(:boolean), not_null: true))

        assert_equal hex("00 0E 01"), writer.to_s
      end
    end
  end
end
