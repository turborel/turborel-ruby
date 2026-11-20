# Errors and Diagnostics

[Contents](README.md)

Every failure reaches a program as a `Turborel::Error`, whether the
server reported it or the driver found it. This chapter tells what an
error carries, which errors end the connection, and how warnings and
notices come.

## What an error carries

A `Turborel::Error` carries its `failure`, and gives its parts:

- `sqlcode`, negative of an exception, and `sqlstate`, five characters;
- `message`, in plain words;
- `rule`, the clause of a standard the failure cites, `nil` if none;
- `position`, where in the statement, counted in characters, `nil` if
  not placed;
- `active`, whether the session's transaction is still active after it;
- `diagnostics`, what the server said beyond the message, where it
  grants `diagnostics`: `severity`, `detail`, `hint`, `context`,
  `schema`, `table`, `column`, `data_type` and `constraint`, each `nil`
  where not told.

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

## Errors that end the connection

A statement's failure leaves the connection as it was. A connection
exception, SQLSTATE class 08 but 08003, ends it, as does credentials
refused as the connection is made: a malformed or too long reply, a
reply out of turn, a closed connection, a wait past its timeout. After
one, `lost?` is true and every method raises that failure again. A
reply whose frame is whole but holds a value the driver cannot take, as
damaged JSON or a truth byte other than 0 or 1, fails its statement
alone with that value's error, SQLCODE -916, or -900 past Turborel's
limits: the rest of the statement's replies are read past first, so the
next statement gets its own, and the connection goes on.
[Appendix B](../appendix/b-errors.md) lists the failures the driver
raises itself.

## Warnings, conditions and notices

A statement that completes with a warning gives its SQLSTATE in
`warning`. Where the server grants `conditions`, each condition a
statement raised, a routine's signalled warnings among them, comes in
its completion: `conditions` gives them and `take_conditions` takes
them. Without `conditions` they come as notices, where the server grants
`notices`; a failing statement's always do.

A notice of the server's own, as 01T01 when `reset` rolls a transaction
back, always comes as a notice. With no handler the connection keeps
the last 64, and `take_notices` takes them; `notice_handler =` gives
each to a handler as it comes, before the reply of the statement that
raised it.

```ruby
conn = Turborel::Client.connect("127.0.0.1", 7422, user: "ann", mechanism: Turborel::Client::Trust.new)
conn.query("CREATE PROCEDURE CHATTY() LANGUAGE SQL CONTAINS SQL SIGNAL SQLSTATE '01ABC' SET MESSAGE_TEXT = 'mind the gap'")
conn.query("CALL CHATTY()")
p conn.take_conditions.map { |condition| [condition.sqlstate, condition.message] }
conn.notice_handler = ->(notice) { puts "notice #{notice.sqlstate}: #{notice.message}" }
conn.reset
conn.terminate
```

```text
[["01ABC", "mind the gap"]]
notice 01T01: [DESIGN] Reset rolled back the transaction that was active
```

## Cancelling

`canceller` gives what cancels the statement a connection runs, from
another thread, over a connection of its own. The statement cancelled
fails with SQLCODE -920, SQLSTATE TB920, and the session goes on.
