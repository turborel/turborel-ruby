# Errors

[Contents](README.md)

## NAME

`Turborel::Error`: every failure the driver raises, the server's or its
own; `Turborel::Failure` and `Turborel::Diagnostics`, what it carries.

## SYNOPSIS

```ruby
error.failure      # => Turborel::Failure
error.sqlcode      error.sqlstate     error.message
error.rule         error.position     error.active
error.diagnostics  # => Turborel::Diagnostics, or nil

Turborel::Failure.new(sqlcode:, sqlstate:, message:, rule:, position:, active:, diagnostics:)
Turborel::Diagnostics.new(severity:, detail:, hint:, context:, schema:, table:, column:, data_type:, constraint:)
```

## DESCRIPTION

`Turborel::Error` is a `StandardError` whose message is its failure's.
Its `failure` says what went wrong: the SQLCODE, negative of an
exception; the SQLSTATE; the message; the clause of a standard the
failure cites (`rule`); where in the statement, counted in characters
(`position`); whether the session's transaction is still `active` after
it; and the server's `diagnostics`, where it grants `diagnostics`: the
failure's severity, ERROR, FATAL, WARNING or NOTICE, its detail, hint
and context, and the schema, table, column, data type and constraint it
concerns, each `nil` where not told. A failure the driver raises itself
has no rule, position or diagnostics, and no transaction active.

A connection exception, SQLSTATE class 08 but 08003, ends the connection
it came on, as does credentials refused, of SQLCODE -919, as the
connection is made; any other failure leaves the connection as it was.
A condition a statement raised, or a notice, is a `Failure` too, of a
class 01 or 02 SQLSTATE, or a `Notice` of its SQLSTATE, message and
diagnostics.

## ERRORS

The failures the driver raises itself, each with the SQLCODE and
SQLSTATE turborel-client gives the same case:

| SQLSTATE | SQLCODE | When |
|---|---|---|
| 08006 | -919 | A server that cannot be reached; a failed TLS handshake; a wait past its timeout; a reply malformed, too long or out of turn; a closed connection; a method needing a capability not granted, or attributes past their bounds, more than 32 or one too long, before anything is sent, the connection kept |
| 28000 | -919 | A password or SCRAM over plain TCP, before anything is sent; a SCRAM server whose final signature is wrong; a channel binding required and impossible |
| 22003 | -301 | A number or a length out of the range of its field |
| 22021 | -301 | A string that cannot be written as UTF-8 |
| 22000 | -301 | A value the protocol cannot carry: of a class the driver does not send, or of a field none of the protocol's |
| 2200N | -301 | An XML value's text that is not well-formed XML content, parsed by `nodes` |
| 0A000 | -900 | Past Turborel's limits: values nested too deep, a JSON value's stored form past 256 MiB |
| TB910 | -910 | An argument none of those a method takes, where turborel-client has no case: a channel binding, a large object's kind |

[Appendix B](../appendix/b-errors.md) lists them with the server's.

## EXAMPLES

```ruby
conn = Turborel::Client.connect("127.0.0.1", 7422, user: "ann", mechanism: Turborel::Client::Trust.new)
begin
  conn.query("INSERT INTO STAFF VALUES (1, 'Ada', 0)")
rescue Turborel::Error => e
  p [e.sqlcode, e.sqlstate, e.message]
  p e.rule
  p [e.diagnostics.severity, e.diagnostics.table, e.diagnostics.constraint, e.diagnostics.detail]
end
begin
  conn.query("SELECT NAME FORM STAFF")
rescue Turborel::Error => e
  p [e.sqlstate, e.position, e.active]
end
p conn.lost?
conn.terminate
```

```text
[-201, "23000", "PRIMARY KEY ANN.STAFF_PRIMARY1 (ID) of ANN.STAFF would be violated: a row of these values is there"]
"X3.135-1986 §6.4 GR2"
["ERROR", "STAFF", "STAFF_PRIMARY1", "the key (1) is held by another row"]
["2A000", 17, true]
false
```

## STANDARD

[PROTOCOL Errors and notices], [PROTOCOL Error 'E'] and [PROTOCOL
Notice 'N'] of [The Native
Protocol](https://github.com/turborel/turborel/blob/main/doc/client/05-protocol.md);
[CLIENT Running statements] and [CLIENT What the server tells] of [The
Client Library](https://github.com/turborel/turborel/blob/main/doc/client/02-library.md).

## SEE ALSO

[Errors and Diagnostics](../user/10-errors.md), [Appendix
B](../appendix/b-errors.md), [Connections](21-connections.md),
[Statements and Cursors](22-statements.md)
