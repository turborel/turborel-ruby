# Pipelines

[Contents](README.md)

## NAME

`Turborel::Client::Pipeline` and `Piped`: a connection's requests
written at once, one outcome each.

## SYNOPSIS

```ruby
pipeline = connection.pipeline
pipeline.query(sql)                     # => Pipeline
pipeline.execute(statement, values = []) # => Pipeline
pipeline.on_error(:continue | :skip)    # => Pipeline
pipeline.size   pipeline.empty?
pipeline.run                            # => Array<Piped>
piped.done   piped.failed   piped.skipped
```

## DESCRIPTION

`run` writes the queued requests a window of 64 KiB at a time
(`Pipeline::PIPELINE_WINDOW`), reads the replies of a window before the
next is written, and gives one `Piped` for each request, in order: its
`done`, a query's `Rows` or another statement's `Completion`; its
`failed`, a `Failure`; or `skipped`. Each request is answered alone, so
by default a failure is its request's own and the rest run. Under
autocommit each is its own transaction, ended with it.

Under `on_error(:skip)` the batch stops at its first failure: a
savepoint is set before each request but the first, named
`TURBOREL_PIPELINE_` and its place; the requests after a failure are
rolled back to the savepoint set after it, or never sent if their window
was not yet written, each `skipped`; the first savepoint is then
released. Its requests are one transaction, committed as the batch ends
under autocommit where it began none.

## ERRORS

| SQLSTATE | SQLCODE | When |
|---|---|---|
| 08006 | -919 | The connection lost during `run`, no outcome given |
| the server's | the server's | A skipping batch whose requests cannot be undone |
| TB910 | -910 | A choice other than `:continue` and `:skip` |

## EXAMPLES

```ruby
conn = Turborel::Client.connect("127.0.0.1", 7422, user: "ann", mechanism: Turborel::Client::Trust.new)
conn.autocommit = true
conn.query("CREATE TABLE BATCH (ID INTEGER PRIMARY KEY)")
outcomes = conn.pipeline.on_error(:skip).query("INSERT INTO BATCH VALUES (1)").query("INSERT INTO BATCH VALUES (1)")
               .query("INSERT INTO BATCH VALUES (2)").run
p outcomes.map { |piped| piped.skipped ? :skipped : (piped.failed || piped.done).sqlstate }
p conn.query("SELECT ID FROM BATCH").rows
conn.terminate
```

```text
["00000", "23000", :skipped]
[[1]]
```

## STANDARD

[PROTOCOL Requests] of [The Native
Protocol](https://github.com/turborel/turborel/blob/main/doc/client/05-protocol.md);
[CLIENT Pipelines] of [Settings, Pipelines and
Pools](https://github.com/turborel/turborel/blob/main/doc/client/02-library-connections.md).

## SEE ALSO

[Pipelines and Pools](../user/08-pipelines-and-pools.md),
[Pools](28-pools.md), [Statements and Cursors](22-statements.md)
