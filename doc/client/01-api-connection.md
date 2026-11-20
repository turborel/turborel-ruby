# Turborel::Connection

[Contents](README.md)

## NAME

`Turborel.connect` and `Turborel::Connection`: the plain API's
connection, in the manner of the pg gem's.

## SYNOPSIS

```ruby
Turborel.connect(uri = nil, **settings) { |variable| ... }   # => Connection
Turborel.connect(settings)                                   # settings a Turborel::Client::Settings

connection.exec(sql)                        # => Result
connection.exec_params(sql, params)         # => Result
connection.prepare(name, sql)               # => Result, of no rows
connection.exec_prepared(name, params = []) # => Result
connection.deallocate(name)
connection.transaction { |connection| ... } # => the block's value
connection.autocommit   connection.autocommit = on   connection.in_transaction?
connection.client                           # => Turborel::Client::Connection
connection.close   connection.finish   connection.finished?
```

## DESCRIPTION

`Turborel.connect` lays the settings given by name, each a name of
`Turborel::Client::Options`, over those of the URI, then resolves them
as `Turborel::Client::Settings.resolve` does, the environment's
variables read by the block, ENV's without one, and connects by them.

`exec` runs a statement's text. `exec_params` runs one with `?`
parameters, a value of `params` for each, as Appendix A writes it: it is
prepared, executed and destroyed. `prepare` prepares a statement under a
name of the program's, destroying one prepared before under the name, as
PREPARE does; its result has the columns the statement will give and no
rows. `exec_prepared` executes it with values, and `deallocate` destroys
it. Each gives a `Turborel::Result`.

A connection's autocommit is off, as Turborel's is: a statement begins a
transaction, which lasts until COMMIT or ROLLBACK. `autocommit = true`
makes each statement its own transaction. `transaction` runs the block
in a transaction of its own, autocommit off within it, committed as the
block ends and rolled back as it raises, the exception raised again.

`client` is the low-level connection beneath, for what the plain API
has no place for: large objects by locator, copy, import and export,
cursors, pipelines, notices and the session's status. `close`, or
`finish`, ends the session.

## ERRORS

Every failure is a `Turborel::Error`, carrying the server's failure: its
SQLCODE, SQLSTATE, message, the rule it cites, its position and its
diagnostics.

| SQLSTATE | SQLCODE | When |
|---|---|---|
| 08001 | -919 | Settings that cannot be read, a name of no setting, or no server kept |
| 28000 | -919 | A user refused, or a password over plain TCP |
| 26000 | -921 | `exec_prepared` or `deallocate` of a name no statement is prepared under, as EXECUTE gives it |
| TB910 | -910 | Parameters' values that are not an `Array`; `transaction` while a transaction is active |
| the server's | the server's | A statement's failure |

## EXAMPLES

```ruby
conn = Turborel.connect("turborel://ann@127.0.0.1:7422/?tls_mode=disable")
conn.exec("CREATE TABLE ACCOUNT (ID INTEGER PRIMARY KEY, BALANCE DECIMAL(10,2))")
conn.exec("COMMIT")
conn.prepare("open", "INSERT INTO ACCOUNT VALUES (?, ?)")
conn.transaction do |t|
  t.exec_prepared("open", [1, BigDecimal("100.00")])
  t.exec_prepared("open", [2, BigDecimal("25.50")])
end
begin
  conn.transaction { |t| t.exec_prepared("open", [1, BigDecimal("1.00")]) }
rescue Turborel::Error => e
  puts "#{e.sqlstate}: #{e.message}"
end
puts conn.exec("SELECT SUM(BALANCE) AS TOTAL FROM ACCOUNT").getvalue(0, 0).to_s("F")
conn.exec("COMMIT")
conn.close
```

```text
23000: PRIMARY KEY ANN.ACCOUNT_PRIMARY1 (ID) of ANN.ACCOUNT would be violated: a row of these values is there
125.5
```

## STANDARD

The driver's own, RULES.md D2.

## SEE ALSO

[Turborel::Result](02-api-result.md), [Connections](21-connections.md),
[Settings](26-settings.md), [Installing](../user/01-installing.md)
