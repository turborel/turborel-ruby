# Pipelines and Pools

[Contents](README.md)

This chapter tells how a program sends a batch of requests in one round
trip by a pipeline, shares a bounded set of connections among its
threads by a pool, and holds several named connections by the
SQL-agent.

## Pipelines

A pipeline sends a connection's requests without waiting for each
reply, so a batch costs one round trip, not one a request. `pipeline`
gives one; `query` and `execute` queue requests; `run` writes them and
gives one `Piped` outcome each, in order: what it gave (`done`), how it
failed (`failed`), or whether it was `skipped`. The server answers each
request alone and in turn, so a failure is its request's own, and the
requests after it run. Requests are written a window of 64 KiB at a
time, its replies read before the next window, so a long batch never
leaves client and server each waiting for the other. Under autocommit
each request is its own transaction.

```ruby
conn = Turborel::Client.connect("127.0.0.1", 7422, user: "ann", mechanism: Turborel::Client::Trust.new)
conn.query("CREATE TABLE CREW (ID INTEGER PRIMARY KEY, NAME VARCHAR(10))")
conn.query("COMMIT")
insert = conn.prepare("INSERT INTO CREW VALUES (?, ?)")
outcomes = conn.pipeline.query("INSERT INTO CREW VALUES (1, 'Ada')").execute(insert, [2, "Grace"])
               .execute(insert, [1, "again"]).query("SELECT NAME FROM CREW ORDER BY ID").run
outcomes.each do |piped|
  if piped.failed then p piped.failed.sqlstate
  elsif piped.done.is_a?(Turborel::Client::Rows) then p piped.done.rows
  else p piped.done.sqlstate
  end
end
conn.query("ROLLBACK")
conn.terminate
```

```text
"00000"
"00000"
"23000"
[["Ada"], ["Grace"]]
```

`on_error(:skip)` makes a batch stop at its first failure, the requests
before it kept. The client sets a savepoint before each request but the
first; the requests after a failure are rolled back to the savepoint set
after it, and those of a window not yet written are never sent; each is
`skipped`. Such a batch is one transaction: under autocommit, of a batch
that began none, it is committed as the batch ends. `run` fails, giving
no outcome, if the connection is lost (SQLSTATE 08006), or if a skipping
batch cannot be undone.

## Pools

`Turborel::Client::Pool` keeps a bounded set of connections that a
program's threads share. `get` hands out an idle connection that
answers, or makes one while fewer than `max` are made, or waits for one
to come back, as a `Pooled` whose `connection` is used and which goes
back to the pool as it is `release`d; given a block, `get` gives the
block the connection and releases it after. A pool is made of
`Settings`, or of anything that answers `call` with a new connection.

```ruby
settings = Turborel::Client::Settings.from_uri("turborel://ann@127.0.0.1:7422/?tls_mode=disable")
pool = Turborel::Client::Pool.new(settings, Turborel::Client::PoolConfig.default.with(max: 2))
threads = 4.times.map { |i| Thread.new { pool.get { |conn| conn.query("VALUES #{i}").rows.first.first } } }
p threads.map(&:value)
p pool.counts
```

```text
[0, 1, 2, 3]
[2, 2]
```

A connection comes back reset to the session it logged in with: by the
protocol's Reset, which ends its transaction, prepared statements,
cursors, temporary tables and settings and keeps its user; autocommit
off; then the pool's `reset` statements. Its check is a Ping, which the
server answers without a worker. Of a server that takes neither, the
check is ROLLBACK and the reset one pipeline. A connection lost, whose
reset fails, that has lived its time, or beyond `max_idle` is closed;
one idle past `idle_timeout`, or that does not answer its check, is
closed as `get` meets it, and another taken or made. `get` fails with
SQLSTATE 08001 if none comes back within `wait`. The pool starts no
thread, and each wait is the waiting thread's. [Appendix
C](../appendix/c-settings.md) lists a pool's settings.

## The SQL-agent

`Turborel::Client::Agent` holds a program's connections, each named, one
current, and runs CONNECT, SET CONNECTION and DISCONNECT itself, as
SQL-92's SQL-agent does; every other statement goes to the current
connection. A connector the program gives, anything that answers
`call(server, user)`, makes the connections CONNECT asks for.

```ruby
port = 7422
connector = ->(_server, user) { Turborel::Client.connect("127.0.0.1", port, user: user || "ann", mechanism: Turborel::Client::Trust.new) }
agent = Turborel::Client::Agent.new(connector)
agent.query("CONNECT TO 'db' AS 'reports' USER 'bob'")
agent.query("CONNECT TO 'db' AS 'main'")
agent.query("SET CONNECTION 'reports'")
p agent.query("VALUES CURRENT_USER").rows
agent.query("ROLLBACK")
p agent.query("DISCONNECT ALL").sqlstate
```

```text
[["BOB"]]
"00000"
```
