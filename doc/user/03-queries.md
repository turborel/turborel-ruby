# Running Queries

[Contents](README.md)

A connection runs one statement at a time in its session. This chapter
tells how a program runs a statement, reads a query's rows, all at once
or a batch at a time, and reads what the server tells of each statement.
Its examples run as ANN, the database's owner, whose schema was made by
`CREATE SCHEMA AUTHORIZATION ANN`.

## A statement and its outcome

`query(sql)` runs one SQL statement and gives its outcome: a query's
`Rows`, its `columns` and its `rows`, each row an `Array` of a value for
each column; or any other statement's `Completion`, its `sqlcode`, 0 or
100, and its `sqlstate`. A statement that finds no row completes with
SQLCODE 100, SQLSTATE 02000.

```ruby
conn = Turborel::Client.connect("127.0.0.1", 7422, user: "ann", mechanism: Turborel::Client::Trust.new)
conn.query("CREATE TABLE STAFF (ID INTEGER PRIMARY KEY, NAME VARCHAR(20), PAY DECIMAL(8,2))")
conn.query("INSERT INTO STAFF VALUES (1, 'Ada', 5200.00), (2, 'Grace', 6100.50)")
result = conn.query("SELECT ID, NAME, PAY FROM STAFF ORDER BY ID")
p result.columns.map(&:name)
result.rows.each { |id, name, pay| puts "#{id} #{name} #{pay.to_s("F")}" }
done = conn.query("DELETE FROM STAFF WHERE ID = 9")
p [done.sqlcode, done.sqlstate]
conn.query("COMMIT")
conn.terminate
```

```text
["ID", "NAME", "PAY"]
1 Ada 5200.0
2 Grace 6100.5
[100, "02000"]
```

A column is a `Turborel::Column`: its `name`, `nil` if it has none, its
`type`, a `Turborel::DataType`, and whether it is known `not_null`. A
value is read as Ruby has it where Ruby has one: `nil` for null, a
`String`, an `Integer` of an exact number of scale 0 and a `BigDecimal`
of another, a `Float`, `true` or `false`, an `Array`. Every other comes
as one of the driver's value classes, [Appendix A](../appendix/a-types.md)
mapping each. A statement that fails raises its `Turborel::Error`, as
[Errors and Diagnostics](10-errors.md) tells.

## Rows a batch at a time

`query_into(sql, sink)` gives a query's rows to `sink` as they come,
so no more than a batch is held: its `columns(columns)` first, then its
`rows(rows)` once for each batch the server sends. It gives the number
of rows, or another statement's `Completion`.

```ruby
conn = Turborel::Client.connect("127.0.0.1", 7422, user: "ann", mechanism: Turborel::Client::Trust.new)
sink = Object.new
def sink.columns(columns) = puts("columns #{columns.map(&:name).join(", ")}")
def sink.rows(rows) = puts("a batch of #{rows.size} rows")
p conn.query_into("SELECT A.ID, B.ID FROM STAFF A, STAFF B", sink)
conn.terminate
```

```text
columns ID, ID
a batch of 4 rows
4
```

## What the server tells of a statement

Each statement's completion tells more, where the server grants it, as
it grants every capability a connection asks for by default:

- `rows_affected`, the rows the statement inserted, updated, deleted or
  merged, or a query's rows once all were read;
- `last_generated`, the identity values an INSERT generated, as SQL
  writes them, in the order of its rows;
- `server_time`, the server's time for the statement in microseconds:
  `total`, `queued` for a worker, and waiting for `locks`;
- `commit_position`, the log position of the last commit, kept until
  the next;
- `warning`, the SQLSTATE of a warning the statement completed with, of
  class 01;
- `conditions`, each condition the statement raised, and
  `take_conditions`, the same taken, so each is told once.

`completion` gives the last statement's whole `Completion`.

```ruby
conn = Turborel::Client.connect("127.0.0.1", 7422, user: "ann", mechanism: Turborel::Client::Trust.new)
conn.query("CREATE TABLE ORDERS (ID INTEGER GENERATED ALWAYS AS IDENTITY, ITEM VARCHAR(20))")
conn.query("INSERT INTO ORDERS (ITEM) VALUES ('jam'), ('tea')")
p conn.rows_affected
p conn.last_generated
p conn.server_time.to_h.keys
conn.query("COMMIT")
p conn.commit_position.positive?
conn.query("SELECT SUM(V) FROM (VALUES (CAST(NULL AS INTEGER)), (1)) AS T(V)")
p conn.warning
p conn.take_conditions.map(&:message)
conn.terminate
```

```text
2
["1", "2"]
[:total, :queued, :locks]
true
"01003"
["the statement completed with warning: null value eliminated in set function"]
```

## Several statements in one request

`query_many(sql)` runs a text of several statements in one request,
each in turn. It gives a `Ran`: each statement's outcome, and the
failure of the statement that stopped the rest, `nil` if none did.
`query_attributes=` sets attributes, each a name and a value, that every
later statement carries until they are set again, as SQL's
QUERY_ATTRIBUTE reads them.

```ruby
conn = Turborel::Client.connect("127.0.0.1", 7422, user: "ann", mechanism: Turborel::Client::Trust.new)
ran = conn.query_many("INSERT INTO STAFF VALUES (3, 'Edsger', 4800.00); SELECT COUNT(*) FROM STAFF; " \
                      "INSERT INTO STAFF VALUES (3, 'Again', 0)")
p ran.outcomes.map { |outcome| outcome.is_a?(Turborel::Client::Rows) ? outcome.rows : outcome.sqlstate }
p ran.failure.sqlstate
conn.query("ROLLBACK")
conn.query_attributes = [["app", "reports"]]
p conn.query("VALUES QUERY_ATTRIBUTE('app')").rows
conn.terminate
```

```text
["00000", [[3]]]
"23000"
[["reports"]]
```

## XML and UUID values

An XML value is read as a `Turborel::Xml`, its `text` its serialization,
and `nodes` parses that text into its elements, attributes, text,
comments and processing instructions. A UUID is read as a
`Turborel::Uuid`, its 16 `octets`, and `text` gives its text.
`Turborel::Xml.new(text:)` makes a parameter of an XML type, and
`Turborel::Uuid.parse(text)` or `Turborel::Uuid.new(octets:)` one of
UUID.

```ruby
conn = Turborel::Client.connect("127.0.0.1", 7422, user: "ann", mechanism: Turborel::Client::Trust.new)
conn.query("CREATE TABLE NOTES (ID UUID, BODY XML)")
insert = conn.prepare("INSERT INTO NOTES VALUES (?, ?)")
conn.execute(insert, [Turborel::Uuid.parse("919108f7-52d1-4320-9bac-f847db4148a8"),
                      Turborel::Xml.new(text: '<note to="Ada">tea at four</note>')])
id, body = conn.query("SELECT ID, BODY FROM NOTES").rows.first
puts id.text
puts body.text
note, = body.nodes
p [note.name, note.attributes.first.value, note.children.first.text]
conn.query("ROLLBACK")
conn.terminate
```

```text
919108f7-52d1-4320-9bac-f847db4148a8
<note to="Ada">tea at four</note>
["note", "Ada", "tea at four"]
```

A value the server cannot serialize, as an attribute standing alone,
fails the statement that would send it, SQLSTATE 2200W.
