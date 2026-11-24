# Prepared Statements

[Contents](README.md)

A statement prepared once runs as many times as a program wants, with
new values each time. This chapter tells how a program prepares a
statement, runs it, reads a query's rows through a cursor, and lets the
statement go.

## Preparing and executing

`prepare(sql)` prepares a statement whose dynamic parameters are written
`?`, and gives a `Statement`: its `parameters`, each a
`Turborel::Parameter` of the type its `?` takes, and a query's
`columns`. `execute(statement, values)` runs it with a value for each
parameter, and gives a query's `Rows`, all of them, or another
statement's `Completion`. A prepared statement stays valid across
transactions; `deallocate` lets it go.

```ruby
conn = Turborel::Client.connect("127.0.0.1", 7422, user: "ann", mechanism: Turborel::Client::Trust.new)
by_id = conn.prepare("SELECT NAME FROM STAFF WHERE ID = ?")
p by_id.parameters.map { |parameter| parameter.type.kind }
p by_id.columns.map(&:name)
p conn.execute(by_id, [2]).rows
p conn.execute(by_id, [1]).rows
conn.deallocate(by_id)
conn.terminate
```

```text
[:exact]
["NAME"]
[["Grace"]]
[["Ada"]]
```

Values short of the parameters fail, SQLSTATE 07001; a statement that
cannot be prepared, SQLSTATE 42000; a statement deallocated, SQLSTATE
26000.

## Output parameters of a CALL

A CALL's `?` of an OUT or INOUT parameter is a column of the prepared
statement, in the procedure's order, and only its inputs are
parameters. Its `execute` gives one row: each output parameter's value
once the procedure ran.

```ruby
conn = Turborel::Client.connect("127.0.0.1", 7422, user: "ann", mechanism: Turborel::Client::Trust.new)
conn.query("CREATE PROCEDURE SPLIT(IN A INTEGER, OUT HALF INTEGER, INOUT TOTAL INTEGER) LANGUAGE SQL " \
           "CONTAINS SQL BEGIN SET HALF = A / 2; SET TOTAL = TOTAL + A; END")
call = conn.prepare("CALL SPLIT(?, ?, ?)")
p call.parameters.size
p call.columns.map(&:name)
p conn.execute(call, [10, 3]).rows
conn.query("ROLLBACK")
conn.terminate
```

```text
2
["HALF", "TOTAL"]
[[5, 13]]
```

## Cursors

`open_cursor(statement, values, rows)` runs a prepared query and gives
a `Batch` of at most `rows` of its rows, all if 0, and whether the
cursor has `more`. `fetch(statement, rows)` gives the next batch; the
cursor closes once it has given its last row, and `close` closes it
sooner. A statement has one cursor open at a time, unless the cursors
are numbered: `open_cursor_numbered(statement, cursor, values, rows)`
opens the cursor of that number, and `fetch` and `close` take
`cursor:`. `describe_cursor(statement, cursor)` gives an open cursor's
columns, and `describe(statement)` the statement as the server prepares
it now.

```ruby
conn = Turborel::Client.connect("127.0.0.1", 7422, user: "ann", mechanism: Turborel::Client::Trust.new)
conn.query("CREATE TABLE NUMBERS (N INTEGER)")
conn.query("INSERT INTO NUMBERS VALUES (1), (2), (3), (4), (5)")
all = conn.prepare("SELECT N FROM NUMBERS ORDER BY N")
p conn.open_cursor(all, [], 2)
p conn.fetch(all, 2)
p conn.fetch(all)
conn.open_cursor_numbered(all, 1, [], 1)
conn.open_cursor_numbered(all, 2, [], 3)
p conn.fetch(all, 1, cursor: 1).rows
p conn.describe_cursor(all, 2).map(&:name)
conn.close(all, cursor: 1)
conn.close(all, cursor: 2)
conn.query("COMMIT")
conn.terminate
```

```text
#<data Turborel::Client::Batch rows=[[1], [2]], more=true>
#<data Turborel::Client::Batch rows=[[3], [4]], more=true>
#<data Turborel::Client::Batch rows=[[5]], more=false>
[[2]]
["N"]
```

A cursor opened again while it is open, fetched or closed while it is
not, or a statement deallocated while a cursor of it is open, fails
with SQLSTATE 24000. A cursor is read within its transaction, as
[Transactions](05-transactions.md) tells.
