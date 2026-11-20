# frozen_string_literal: true

require "test_helper"

module Turborel
  # Values written as text, as turborel shows them: each expected text is
  # what turborel's own command-line client shows of the value.
  class TextTest < Minitest::Test
    def decimal(precision, scale) = DataType.new(kind: :exact, params: { precision:, scale: })

    def stamp(moment, utc, zone: 0, zoned: false, precision: 0)
      Datetime.new(moment:, utc:, zone:, zoned:, precision:)
    end

    # 2026-11-19 at midnight UTC, in microseconds from 0001-01-01.
    DAY = 63_930_643_200_000_000

    # Verifies: [CLIENT Copying and exporting] numbers as turborel shows
    # them: an exact number at its column's scale; an approximate one as
    # its shortest literal with an exponent; a DECFLOAT plain or with one.
    def test_numbers
      assert_equal(%w[1.50 -123.456 7 0.00 5200.00 1.5],
                   [[BigDecimal("1.5"), decimal(5, 2)], [BigDecimal("-123.456"), decimal(9, 3)], [7, nil],
                    [0, decimal(5, 2)], [5200, decimal(8, 2)], [BigDecimal("1.5"), nil]].map { |v, t| Text.of(v, t) })
      assert_equal(%w[1.5E0 1E2 0E0 -0E0 1E-6 -1.249999968422344E-5 1E22 NaN inf -inf],
                   [1.5, 100.0, 0.0, -0.0, 0.000001, -1.249999968422344e-5, 1e22, Float::NAN, Float::INFINITY,
                    -Float::INFINITY].map { Text.of(_1) })
      assert_equal(%w[1.5 1.5E41 -1.23E-7 0 15000],
                   [[15, -1], [15, 40], [-123, -9], [0, 0], [15, 3]].map do |c, e|
                     Text.of(DecFloat.new(coefficient: c, exponent: e))
                   end)
      assert_equal "1E-40", Text.of(BigDecimal("1e-40"))
    end

    # Verifies: [CLIENT Copying and exporting] datetimes and intervals as
    # their literals' strings, in the value's zone, to its precision.
    def test_datetimes_and_intervals
      assert_equal "2026-11-19", Text.of(stamp(:date, DAY))
      assert_equal "2026-11-19 06:32:03.456789", Text.of(stamp(:timestamp, DAY + 23_523_456_789, precision: 6))
      assert_equal "2026-11-19 06:32:03.4+05:30",
                   Text.of(stamp(:timestamp, DAY + 3_723_400_000, zone: 330, zoned: true, precision: 1))
      assert_equal(["01:02:03", "23:00:00+00:00", "0001-01-01", "1969-12-31 23:59:59.5"],
                   [stamp(:time, 3_723_000_000), stamp(:time, 82_800_000_000, zoned: true), stamp(:date, 0),
                    stamp(:timestamp, 62_135_596_799_500_000, precision: 1)].map { Text.of(_1) })
      day = Interval.new(start: :day, finish: :second, leading: 2, fraction: 3,
                         units: -((3 * 86_400_000_000) + 3_723_456_000))

      assert_equal(["-3 01:02:03.456", "2-03", "100:30"],
                   [day, Interval.new(start: :year, finish: :month, leading: 2, fraction: 0, units: 27),
                    Interval.new(start: :hour, finish: :minute, leading: 3, fraction: 0, units: 361_800_000_000)]
                     .map { Text.of(_1) })
    end

    # Verifies: [CLIENT Copying and exporting] strings, binary strings,
    # truth values, large objects, UUIDs, XML and a plug-in's values as
    # turborel shows them.
    def test_other_values
      clob = Lob.new(kind: :character, data: "abc", locator: nil, octets: 3, characters: 3)
      located = Lob.new(kind: :binary, data: nil, locator: 1, octets: 9, characters: 9)

      assert_equal(["x", "0A", "TRUE", "FALSE", "abc", "0102", "<BINARY LARGE OBJECT of 9 octets>",
                    "<CHARACTER LARGE OBJECT of 3 characters>", "919108f7-52d1-4320-9bac-f847db4148a8",
                    "<a>b</a>", "POINT (1 2)", "NULL"],
                   ["x", "\n".b, true, false, clob, clob.with(kind: :binary, data: "\x01\x02".b), located,
                    located.with(kind: :character, characters: 3),
                    Uuid.parse("919108f7-52d1-4320-9bac-f847db4148a8"), Xml.new(text: "<a>b</a>"),
                    Extension.new(name: "ST_GEOMETRY", text: "POINT (1 2)", bytes: ""), nil].map { Text.of(_1) })
    end

    # Verifies: [CLIENT Copying and exporting] a composite value as its
    # literal, each part its own literal.
    def test_literals
      element = decimal(4, 2)
      array = DataType.new(kind: :array, params: { max: 2, element: })

      assert_equal "ARRAY[1.50, -2.25]", Text.of([BigDecimal("1.5"), BigDecimal("-2.25")], array)
      assert_equal "ARRAY[DATE '2026-01-02']", Text.of([stamp(:date, DAY - (321 * 86_400_000_000))])
      minute = Interval.new(start: :minute, finish: :minute, leading: 2, fraction: 0, units: 300_000_000)

      assert_equal "ROW(INTERVAL '5' MINUTE(2), CAST('1.5' AS DECFLOAT), X'AB')",
                   Text.of(Row.new(values: [minute, DecFloat.new(coefficient: 15, exponent: -1), "\xAB".b]))
      assert_equal "MULTISET[1, 1, 2]", Text.of(Multiset.new(values: [1, 1, 2]))
      assert_equal "ARRAY['it''s', NULL, TRUE]", Text.of(["it's", nil, true])
      assert_equal "S.T(1, REF(0102), UUID '919108f7-52d1-4320-9bac-f847db4148a8')",
                   Text.of(Structured.new(schema: "S", name: "T",
                                          attributes: [1, Reference.new(octets: "\x01\x02".b),
                                                       Uuid.parse("919108f7-52d1-4320-9bac-f847db4148a8")]))
      assert_equal "ARRAY[INTERVAL -'1' SECOND(2, 0), INTERVAL '1-02' YEAR(2) TO MONTH, " \
                   "INTERVAL '1:00:00.5' HOUR(2) TO SECOND(1)]",
                   Text.of([Interval.new(start: :second, finish: :second, leading: 2, fraction: 0, units: -1_000_000),
                            Interval.new(start: :year, finish: :month, leading: 2, fraction: 0, units: 14),
                            Interval.new(start: :hour, finish: :second, leading: 2, fraction: 1, units: 3_600_500_000)])
    end

    # Verifies: [CLIENT Copying and exporting] large objects, JSON and XML
    # as literals within a composite value.
    def test_nested_literals
      clob = Lob.new(kind: :character, data: "o'k", locator: nil, octets: 3, characters: 3)

      assert_equal "ROW('o''k', X'01', JSON('{\"a\":1}'), XMLPARSE(CONTENT '<a/>' PRESERVE WHITESPACE), " \
                   "<BINARY LARGE OBJECT of 2 octets>)",
                   Text.of(Row.new(values: [clob, clob.with(kind: :binary, data: "\x01".b),
                                            Json.new(value: { "a" => 1 }), Xml.new(text: "<a/>"),
                                            Lob.new(kind: :binary, data: nil, locator: 2, octets: 2, characters: 2)]))
    end

    # Verifies: [CLIENT Copying and exporting] a JSON value as turborel
    # writes its text: no white space, strings escaped, an exact number's
    # digits and scale, an approximate one's literal, a DECFLOAT plain; of
    # a datetime or a number not finite, why there is none.
    def test_json_text
      item = { "s" => "\u0001\\\"\n\t\b\f\r/é",
               "n" => [Decimal.new(units: 150, scale: 2), 2, 1.5, 1.0, 0.0, nil, true, false],
               "d" => DecFloat.new(coefficient: 15, exponent: 30), "b" => BigDecimal("0.25"), "y" => :sym }

      assert_equal '{"s":"\u0001\\\\\\"\n\t\b\f\r/é","n":[1.50,2,1.5E0,1.0E0,0E0,null,true,false],' \
                   '"d":15000000000000000000000000000000,"b":0.25,"y":"sym"}',
                   Text::Json.of(item)
      assert_equal "<[ISO/IEC 9075-2:2023 §9.43 GR2a ii] no JSON text parses to a datetime>",
                   Text.of(Json.new(value: [stamp(:date, DAY)]))
      assert_equal "<[ISO/IEC 9075-2:2023 §9.43 GR2a ii] no JSON text parses to an approximate number " \
                   "that is not finite>",
                   Text.of(Json.new(value: Float::NAN))
    end
  end
end
