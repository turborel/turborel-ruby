# Appendix A: Types

[Contents](README.md)

How each value of the native protocol is read into Ruby, and which Ruby
values are written as each. A value's tag says how it is written, not
its column's type: a CHARACTER VARYING value comes with tag 1, as a
CHARACTER value does. The protocol's data types, the types of columns
and parameters, are in the second table.

## Values

| Tag | Value | Read as | Written from |
|---|---|---|---|
| 0 | null | `nil` | `nil` |
| 1 | character string | `String`, UTF-8 | `String` of any encoding but binary, written as UTF-8 |
| 2 | exact number | `Integer` of scale 0; `BigDecimal` of a scale above 0 | `Integer`, a finite `BigDecimal`, or a `Turborel::Decimal` |
| 3 | approximate number | `Float`, NaN and -0.0 as they came | `Float` |
| 4 | a plug-in's value | `Turborel::Extension`: name, text, bytes | `Turborel::Extension`, as it came |
| 6 | binary string | `String`, binary | `String` of binary encoding |
| 8, 9, 11 | date, time, timestamp | `Turborel::Datetime` | `Turborel::Datetime` |
| 13 | interval | `Turborel::Interval` | `Turborel::Interval` |
| 14 | truth value | `true` or `false`; unknown comes as `nil` | `true` or `false` |
| 15 | decimal floating point | `Turborel::DecFloat` | `Turborel::DecFloat` |
| 16 | array | `Array` | `Array` |
| 17 | row | `Turborel::Row` | `Turborel::Row` |
| 20 | large object, whole | `Turborel::Lob` holding its `data` | `Turborel::Lob` holding its `data` |
| 21 | large object, by locator | `Turborel::Lob` holding its `locator` | `Turborel::Lob` holding its `locator` |
| 22 | multiset | `Turborel::Multiset` | `Turborel::Multiset` |
| 23 | structured value | `Turborel::Structured` | `Turborel::Structured` |
| 24 | reference | `Turborel::Reference` | `Turborel::Reference` |
| 25 | JSON | `Turborel::Json`, its `value` Ruby's | `Turborel::Json` |
| 26 | XML | `Turborel::Xml`, its serialization as CONTENT | `Turborel::Xml` |
| 27 | UUID | `Turborel::Uuid`, its 16 octets | `Turborel::Uuid` |

A value of a subclass is written as its class's. A value of any other
class fails with SQLSTATE 22000, before anything is sent.

The server writes no other tag. A value of tag 5, 7, 10 or 12, of
CHARACTER VARYING, BINARY VARYING, TIME WITH TIME ZONE or TIMESTAMP
WITH TIME ZONE, is read as tag 1, 6, 9 or 11 is, as turborel-protocol's
reader reads it; one of tag 18 or 19, a large object's stored form, or
of any other tag, is malformed, and loses the connection, SQLSTATE
08006, as a value that cannot be decoded does.

The bounds of each:

- **Exact numbers** carry units, an `i128`, and a scale, a `u32`: the
  number is the units divided by ten to the scale. Every such number is
  read exactly, the whole of the `i128` and every scale. A `BigDecimal`
  is written at the least scale that holds it, so 1.50 is written as 15
  at scale 1, the same number; one whose units at that scale do not fit
  an `i128`, or that is NaN or infinite, fails with SQLSTATE 22003. A
  `Turborel::Decimal` is written at its own `units` and `scale`.
- **Datetimes**: `moment` is `:date`, `:time` or `:timestamp`; `utc` the
  instant, an `i64`: of a timestamp, microseconds in UTC from
  0001-01-01 00:00:00; of a date, the instant of its midnight; of a time,
  microseconds from midnight UTC, within a day; `zone` the displacement in
  minutes, an `i16`, from -12:59 to +14:00 as the server writes it;
  `zoned` whether the type is WITH TIME ZONE; `precision` the seconds'
  fractional digits, a `u8`. Without a zone, the displacement is the one
  the value is shown in.
- **Intervals**: `start` and `finish` are the qualifier's fields,
  `:year`, `:month`, `:day`, `:hour`, `:minute` or `:second`; `leading`
  and `fraction` its precisions; `units`, an `i128`, months of a
  year-month interval and microseconds of a day-time one.
- **DECFLOAT**: `coefficient`, of at most 34 digits and no trailing zero,
  times ten to `exponent`; zero is 0 and 0. A value, tag 15, not in that
  form fails, read or written. Within a JSON value, a DECFLOAT is read as
  Turborel reads it, rounded half to even to 34 digits, and fails only
  out of range.
- **Large objects**: `kind` is `:character` or `:binary`; a whole one's
  `data` is UTF-8 of a character one, and its `octets` and `characters`
  its lengths; a locator lasts until its transaction ends.
- **Arrays, rows, multisets and structured values** nest at most 16 deep,
  and a multiset holds at most 65,535 elements.
- **JSON**: a JSON value's item is read as Ruby values: an object as a
  `Hash` in written order, keeping the first member written of a key, as
  a member accessor takes it; an array as an `Array`; a string as a
  `String`; a number as an `Integer`, a `Turborel::Decimal`, a
  `Turborel::DecFloat` or a `Float`, as it is stored; a datetime as a
  `Turborel::Datetime`; `true`, `false`, and `nil` for the JSON null. Any
  of these is written back, a `Symbol` as a string, a `Hash`'s keys
  being `String`s or `Symbol`s, a `BigDecimal` too. An exact number is
  stored in the narrowest of its forms. A decimal keeps the scale it was
  written with: a `Turborel::Decimal` of `units` 150 and `scale` 2 is
  1.50, read and written so, its `to_s` "1.50" and its `to_d` the
  `BigDecimal`; a `BigDecimal`, which keeps no scale, is written at the
  least scale that holds it. Arrays and objects nest at most 128 deep, and a
  stored form is at most 256 MiB. Damaged octets fail the connection.
- **UUIDs** are 16 octets, no more and no fewer.

## Data types

A column's or a parameter's type is a `Turborel::DataType`: its `kind`,
and its `params`, a `Hash` of what the kind writes after its tag. A
distinct type comes as its source type.

| Tag | `kind` | `params` |
|---|---|---|
| 1 | `:character` | `length`, `units` (`:characters` or `:octets`) |
| 2 | `:exact` | `precision`, `scale` |
| 3 | `:approximate` | `precision` |
| 4 | `:extension` | `name`, and `params`, at most two `Integer`s |
| 5 | `:varying` | `length`, `units` |
| 6 | `:binary` | `length` |
| 7 | `:varbinary` | `length` |
| 8 | `:date` | `precision` |
| 9 | `:time` | `precision` |
| 10 | `:time_zoned` | `precision` |
| 11 | `:timestamp` | `precision` |
| 12 | `:timestamp_zoned` | `precision` |
| 13 | `:interval` | `start`, `finish`, `leading`, `fraction` |
| 14 | `:boolean` | none |
| 15 | `:decfloat` | `precision` |
| 16 | `:array` | `max`, 1 to 65,535, and `element`, a `DataType` |
| 17 | `:row` | `fields`, each a name and a `DataType` |
| 18 | `:clob` | `length`, `units` |
| 19 | `:blob` | `length`, `units` |
| 22 | `:multiset` | `element` |
| 23 | `:structured` | `schema`, `name`, `supertypes`, each a schema and a name |
| 24 | `:reference` | the referenced type's `schema`, `name` and `supertypes`, and `scope`, a schema and a name or `nil` |
| 25 | `:json` | none |
| 26 | `:xml` | `primary` (`:document`, `:content` or `:sequence`), `secondary` (`:untyped`, `:any` or `:xmlschema`), and of `:xmlschema` its `schema`: the schema's `schema` and `name`, its `namespace` and its `element`, each `nil` where none |
| 27 | `:uuid` | none |

A type of a tag not listed fails the connection.
