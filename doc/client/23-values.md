# Values

[Contents](README.md)

## NAME

The value classes: what each value of the protocol is read into, and
written from.

## SYNOPSIS

```ruby
Turborel::Datetime.new(moment:, utc:, zone:, zoned:, precision:)
Turborel::Interval.new(start:, finish:, leading:, fraction:, units:)
Turborel::Decimal.new(units:, scale:)
Turborel::DecFloat.new(coefficient:, exponent:)
Turborel::Lob.new(kind:, data:, locator:, octets:, characters:)
Turborel::Row.new(values:)
Turborel::Multiset.new(values:)
Turborel::Structured.new(schema:, name:, attributes:)
Turborel::Reference.new(octets:)
Turborel::Json.new(value:)
Turborel::Xml.new(text:)
Turborel::Uuid.new(octets:)
Turborel::Extension.new(name:, text:, bytes:)
Turborel::DataType.new(kind:, params:)
Turborel::Column.new(name:, type:, not_null:)
Turborel::Parameter.new(varying:, type:)
```

## DESCRIPTION

A value of the protocol is read as a Ruby value where Ruby has one:
`nil`, a `String`, an `Integer` or a `BigDecimal`, a `Float`, `true` or
`false`, or an `Array`. Every other is read as one of the classes above,
each an immutable `Data` whose fields are those the protocol writes, so a
value read and written back is the value read. [Appendix
A](../appendix/a-types.md) maps each tag to its class and gives the
bounds of each field.

A value given as a parameter, or as a field of a row copied in, is
written from the same classes. An exact number comes as an `Integer`
where its scale is 0 and as a `BigDecimal` otherwise, exactly in both
cases. Within a JSON value a decimal is read as a `Turborel::Decimal`,
its `units` and `scale` as written, so 1.50 stays 1.50; one is written
at its own scale wherever it is given.

What the server describes of a result's columns and a statement's
parameters is a `Column` and a `Parameter`, each with its `DataType`.

How a program receives values and passes them, through the plain API
and the low-level client, is told with them, at milestones M3 and M7.

## ERRORS

| SQLSTATE | SQLCODE | When |
|---|---|---|
| 22000 | -301 | A value of a class the driver does not send, or a datetime's moment, an interval's field or a large object's kind that is none of the protocol's |
| 0A000 | -900 | Values nested deeper than 16, 128 within a JSON value, or a JSON value's stored form longer than 256 MiB |
| 22003 | -301 | A number out of the range of its field: an `Integer` or `BigDecimal` whose units do not fit an `i128`, a NaN or infinite `BigDecimal`, a displacement that does not fit an `i16`, a DECFLOAT not in its one form, a UUID not of 16 octets |
| 22021 | -301 | A string that cannot be written as UTF-8 |
| 08006 | -919 | A value received that is malformed: a tag no value has, a body cut short, a DECFLOAT value not in its one form, damaged JSON |

## EXAMPLES

```ruby
stamp = Turborel::Datetime.new(moment: :timestamp, utc: 0, zone: 60, zoned: true, precision: 6)
stamp.zone  # => 60
```

## STANDARD

[PROTOCOL Values], [PROTOCOL Data types] and [PROTOCOL Composite
fields] of
[The Native Protocol](https://github.com/turborel/turborel/blob/main/doc/client/05-protocol.md);
the JSON value's binary tree, Turborel's
[RULES.md](https://github.com/turborel/turborel/blob/main/RULES.md) D89.

## SEE ALSO

[Appendix A: Types](../appendix/a-types.md), [Errors](30-errors.md)
