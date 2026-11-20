# Transactions

[Contents](README.md)

This chapter tells how a session's transaction begins and ends, how a
cursor and a large object's locator keep it, and how a session is reset,
changes its user, and tells its settings.

## Beginning and ending

A transaction begins with the first statement and lasts until COMMIT or
ROLLBACK, as SQL-92 has it. `in_transaction?` says whether the
session's transaction is active, as the server said after the last
statement. `autocommit = true` makes each statement `query`,
`query_into`, `execute` or `query_many` runs its own transaction
instead: the server commits it as the statement succeeds, or rolls it
back as it fails, within the same request, so no COMMIT is sent. A
commit that fails then raises its failure in place of the statement's
completion, the transaction rolled back.

```ruby
conn = Turborel::Client.connect("127.0.0.1", 7422, user: "ann", mechanism: Turborel::Client::Trust.new)
p conn.in_transaction?
conn.query("INSERT INTO STAFF VALUES (3, 'Edsger', 4800.00)")
p conn.in_transaction?
conn.query("ROLLBACK")
p conn.in_transaction?
conn.autocommit = true
conn.query("INSERT INTO STAFF VALUES (3, 'Edsger', 4800.00)")
p conn.in_transaction?
conn.query("CREATE TABLE CHECKED (N INTEGER, CONSTRAINT POSITIVE CHECK (N > 0) INITIALLY DEFERRED)")
begin
  conn.query("INSERT INTO CHECKED VALUES (-1)")
rescue Turborel::Error => e
  p [e.sqlcode, e.sqlstate]
end
conn.terminate
```

```text
false
true
false
false
[-913, "40002"]
```

## Cursors and locators

A cursor `open_cursor` opens is read within its transaction. Under
autocommit, where the server grants `fetch-ends`, as it does by
default, the transaction ends as the cursor does: committed once its
last row is fetched or it is closed, rolled back if a fetch fails.
Without autocommit the transaction goes on until COMMIT or ROLLBACK.

A large object a query sends by its locator is valid only within its
transaction, so a result that sent one keeps the transaction active,
under autocommit too, until the program ends it.

## Resetting, changing user, and the session's settings

`reset` puts the session back as it was at login: its transaction
rolled back, its prepared statements, cursors, temporary tables and
settings gone, its user and cancel key kept. A transaction rolled back
so is told by a notice of SQLSTATE 01T01. `change_user(user,
mechanism)` authenticates the connection again as another user, by any
mechanism, and renews the session as `reset` does, under a new cancel
key, no transaction active after it; one refused closes the connection.
`ping` asks whether the server answers, taking none of its workers.

The server tells the session's settings as it begins, after `reset` or
`change_user`, and after each statement that changes one: `setting(name)`
gives one as last told, with no round trip, and `settings` all of them.

```ruby
conn = Turborel::Client.connect("127.0.0.1", 7422, user: "ann", mechanism: Turborel::Client::Trust.new)
conn.query("SET TIME ZONE INTERVAL '+02:00' HOUR TO MINUTE")
p conn.setting("SESSION.TIME_ZONE")
conn.query("VALUES 1")
conn.reset
p conn.take_notices.map(&:sqlstate)
p conn.setting("SESSION.TIME_ZONE")
conn.ping
conn.change_user("bob", Turborel::Client::Trust.new)
p [conn.authorization, conn.setting("OWNER")]
conn.terminate
```

```text
"+02:00"
["01T01"]
"+00:00"
["BOB", "NO"]
```

`ping`, `reset`, `change_user`, `query_many`, query attributes,
`describe` and numbered cursors each need a capability the server
grants by default. Asked of a server that did not grant it, each fails
before anything is sent, SQLSTATE 08006, the connection kept.
