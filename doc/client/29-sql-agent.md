# The SQL-agent

[Contents](README.md)

## NAME

`Turborel::Client::Agent`: a program's named connections, one current,
and SQL-92's connection statements.

## SYNOPSIS

```ruby
agent = Turborel::Client::Agent.new(connector, connection = nil)  # connector.call(server, user) => Connection
agent.query(sql)                  # => Rows | Completion
agent.query_into(sql, sink)       # => Integer | Completion
agent.connection_statement(sql)   # => Completion, or nil
agent.current   agent.current_connection   agent.current_name
agent.canceller   agent.warning   agent.lost?   agent.terminate
```

## DESCRIPTION

`query` runs CONNECT TO, SET CONNECTION and DISCONNECT itself, and sends
every other statement to the current connection. CONNECT TO a server AS
a name USER a user, each a character string literal, calls the
connector with the server and the user, or `nil` for TO DEFAULT or no
USER; the connection is named by its name, else its server, read as an
identifier, and made current. SET CONNECTION makes the named one, or
DEFAULT, current. DISCONNECT ends the named one, DEFAULT, CURRENT or
ALL. An agent made with a connection holds it as the default
connection, current. `terminate` ends every connection.

A statement is read as Turborel reads it: after its comments, simple or
bracketed; a name a character string literal, national, introduced by
a character set, or in parts a newline separates. A connection exception
the agent raises, or its refusal to end a connection whose transaction
is active, cites its rule of ISO/IEC 9075:1992 §15, as `rule` gives it,
apart from its message.

## ERRORS

| SQLSTATE | SQLCODE | When |
|---|---|---|
| 08003 | -919 | No current connection, or none of the name |
| 08002 | -919 | CONNECT of a name already established |
| 08001 | -919 | CONNECT to a server that cannot be reached |
| 08004 | -919 | CONNECT the server refuses |
| 0A001 | -900 | CONNECT or SET CONNECTION while the current connection's transaction is active |
| 25000 | -917 | DISCONNECT of a connection whose transaction is active |
| 28000 | -104 | A user that is no authorization identifier |
| 2E000 | -919 | A connection name that is no identifier |
| 42000 | -101, -102, -103 | A connection statement with a comment that does not end, malformed, or naming by a literal no character string literal is |
| 01002 | 0 | DISCONNECT that met an error ending a connection, a warning |

## EXAMPLES

```ruby
port = 7422
connector = ->(_server, user) { Turborel::Client.connect("127.0.0.1", port, user: user || "ann", mechanism: Turborel::Client::Trust.new) }
agent = Turborel::Client::Agent.new(connector)
agent.query("CONNECT TO 'db' AS 'one'")
begin
  agent.query("CONNECT TO 'db' AS 'one'")
rescue Turborel::Error => e
  p [e.sqlstate, e.message]
end
agent.terminate
```

```text
["08002", "the connection ONE is established"]
```

## STANDARD

[CLIENT The SQL-agent] of [The Client
Library](https://github.com/turborel/turborel/blob/main/doc/client/02-library.md).

## SEE ALSO

[Pipelines and Pools](../user/08-pipelines-and-pools.md),
[Connections](21-connections.md)
