# Statements and Cursors

[Contents](README.md)

## NAME

`Turborel::Client::Connection`: statements, prepared statements,
cursors, and what the server tells of each; the session's control.

## SYNOPSIS

```ruby
connection.query(sql)                      # => Rows | Completion
connection.query_into(sql, sink)           # => Integer | Completion
connection.query_many(sql)                 # => Ran
connection.prepare(sql)                    # => Statement
connection.execute(statement, values = []) # => Rows | Completion
connection.open_cursor(statement, values = [], rows = 0)                 # => Batch
connection.open_cursor_numbered(statement, cursor, values = [], rows = 0) # => Batch
connection.fetch(statement, rows = 0, cursor: 0)                         # => Batch
connection.close(statement, cursor: 0)
connection.describe(statement)             # => Statement
connection.describe_cursor(statement, cursor = 0) # => Array<Column>
connection.deallocate(statement)

connection.in_transaction?   connection.autocommit   connection.autocommit = on
connection.completion        connection.rows_affected   connection.last_generated
connection.server_time       connection.commit_position connection.warning
connection.conditions        connection.take_conditions
connection.notice_handler = proc   connection.take_notices
connection.query_attributes  connection.query_attributes = [[name, value], ...]
connection.ping   connection.reset   connection.change_user(user, mechanism)

Turborel::Client::Rows.new(columns:, rows:)
Turborel::Client::Statement.new(number:, parameters:, columns:)
Turborel::Client::Batch.new(rows:, more:)
Turborel::Client::Ran.new(outcomes:, failure:)
Turborel::Client::Completion  # sqlcode, sqlstate, active, position, more, rows, generated, conditions, time
Turborel::Client::Timing      # total, queued, locks
Turborel::Client::Notice      # sqlstate, message, diagnostics
```

## DESCRIPTION

`query` runs a statement in the session and gives a query's `Rows`, its
columns and every row, or another statement's `Completion`.
`query_into` gives a query's columns, then each batch of rows as it
comes, to `sink`, whose `columns` and `rows` take them, and gives the
number of rows. `query_many` runs a text of several statements in one
request and gives each outcome, in order, and the `Failure` of the
statement that stopped the rest; a failure that loses the connection is
raised instead.

`prepare` gives a `Statement` numbered by the connection, from 0 up: its
`parameters` in the order of their `?` marks, a statement's inputs
alone, and its `columns`, of a query, or of a CALL each `?` of an OUT or
INOUT parameter. `execute` runs it with a value for each parameter and
gives a query's `Rows`, a CALL's one row of its output parameters, or
another statement's `Completion`. `open_cursor` opens a query's cursor
and gives at most `rows` of its rows, all if 0, as a `Batch` that says
whether the cursor has `more`; `fetch` gives the next; the cursor closes
once its last row is given, or by `close`. `open_cursor_numbered` opens
the cursor of its number, several open at once; `fetch` and `close`
take `cursor:`. `describe` gives the statement as the server prepares it
now, `describe_cursor` an open cursor's columns, and `deallocate` lets
the statement go.

The transaction begins with the first statement and lasts until COMMIT
or ROLLBACK; `in_transaction?` says whether it is active, as the server
said after the last statement. Under `autocommit` each statement
`query`, `query_into`, `execute` and `query_many` run is its own
transaction, ended within its request; a cursor's ends as the cursor
does, where the server grants `fetch-ends`; a result that sent a
locator keeps it.

Each statement's completion tells, where the server grants it, the rows
it changed or a query's rows (`rows_affected`), the identity values an
INSERT generated (`last_generated`), the server's time (`server_time`),
the last commit's log position (`commit_position`), its warning's
SQLSTATE (`warning`) and its conditions (`conditions`,
`take_conditions`). Notices go to `notice_handler` as they come, or are
kept, the last 64, for `take_notices`. `query_attributes` are carried by
every later Query and Execute, where the server grants
`query-attributes`.

`ping` asks whether the server answers. `reset` puts the session back as
it was at login, its user and cancel key kept, telling each setting
again. `change_user` authenticates the connection again as `user` by
`mechanism`, renewing the session under a new cancel key, no
transaction active after it.

## ERRORS

| SQLSTATE | SQLCODE | When |
|---|---|---|
| the server's | the server's | A statement that fails, as the server reports it: 07001 values short of the parameters, 24000 a cursor open or not as the call needs, 26000 no such statement, 37000 a statement that cannot be prepared, 2200W a value with no serialization, 40002 a commit that fails |
| TB920 | -920 | The statement cancelled |
| 28000 | -919 | A `change_user` refused, which closes the connection |
| 08006 | -919 | A method needing a capability the server did not grant, before anything is sent, the connection kept; a reply out of turn, malformed or too long, or a closed connection, the connection lost |

## EXAMPLES

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

## STANDARD

[PROTOCOL Query 'Q'], [PROTOCOL Prepare 'P'], [PROTOCOL Execute 'E'],
[PROTOCOL Fetch 'F'], [PROTOCOL Close 'C'], [PROTOCOL Deallocate 'D'],
[PROTOCOL Describe 'Y'], [PROTOCOL Ping 'G'], [PROTOCOL Reset 'W'],
[PROTOCOL ChangeUser 'U'], [PROTOCOL Complete 'K'] and [PROTOCOL Status
'T'] of [The Native Protocol](https://github.com/turborel/turborel/blob/main/doc/client/05-protocol.md);
[CLIENT Running statements], [CLIENT Prepared statements], [CLIENT XML
values], [CLIENT UUIDs], [CLIENT What the server tells] and [CLIENT
Controlling the session] of [The Client
Library](https://github.com/turborel/turborel/blob/main/doc/client/02-library.md).

## SEE ALSO

[Running Queries](../user/03-queries.md), [Prepared
Statements](../user/04-prepared-statements.md),
[Transactions](../user/05-transactions.md), [Errors](30-errors.md),
[Values](23-values.md)
