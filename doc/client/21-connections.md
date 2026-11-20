# Connections

[Contents](README.md)

## NAME

`Turborel::Client`: connections to a server, the low-level client's.

## SYNOPSIS

```ruby
Turborel::Client.connect_to(target, user:, mechanism:, timeouts: DEFAULT_TIMEOUTS, offer: Offers.default)
Turborel::Client.connect(host, port = 7422, user:, mechanism:)
Turborel::Client.connect_local(path, user:, mechanism:)
Turborel::Client::Connection.open(io, user:, mechanism:, offer: Offers.default)
Turborel::Client::Connection.open_within(io, user:, mechanism:, timeouts: DEFAULT_TIMEOUTS, offer: Offers.default)

Turborel::Client::Targets.tcp(host, port = 7422)
Turborel::Client::Targets.local(path)
Turborel::Client::Targets.tls(host, port, server_name:, context:)
Turborel::Client::TLS.context(roots: nil, platform: false, certificate: nil, key: nil)
Turborel::Client::Timeouts.new(connect:, read:)
Turborel::Client::Offers.default | .none | .compressed(offer) | .attribute(offer, name, value)

Turborel::Client::Trust.new
Turborel::Client::Password.new(password)
Turborel::Client::Certificate.new
Turborel::Client::Scram.new(password, clear: false, binding: :prefer, cache: nil)
Turborel::Client::KeyCache.new

connection.authorization   connection.server     connection.granted
connection.granted?(name)  connection.setting(name)  connection.settings
connection.read_timeout    connection.read_timeout = seconds
connection.max_body        connection.max_body = bytes
connection.target          connection.canceller  connection.lost?
connection.terminate
canceller.cancel(within = 10)
```

## DESCRIPTION

`connect_to` connects to the server a `Target` names, as `user`, proved
by `mechanism`, waiting as `timeouts` say and asking for what `offer`
asks; over TLS the mechanism is bound to the connection first.
`Connection.open` logs in over any stream the program opened, which then
answers for its own privacy and waits, `terminate`'s too;
`Connection.open_within` logs in over one that bounds itself, a socket
or TLS over one, and bounds it as `timeouts` say. `terminate` reads past
a Notice or a Status to the Error a failing commit sends. [Connecting](../user/02-connecting.md)
tells the mechanisms, TLS, timeouts and what a connection is told.

The SCRAM key cache keeps the keys a password derived after a login, so
a later login meeting the same salt and iterations skips their slow
derivation. A `Scram` given `cache:` uses it. An entry is found by the
salt, the iterations and a tag of the password under a random secret of
the cache's own, so the cache holds neither the password nor anything it
could be guessed from; it holds at most 64 entries, the oldest dropped
first, and drops an entry when a login that used it fails. `lookups`
gives its hits and misses. A cache may be shared by threads.

## ERRORS

| SQLSTATE | SQLCODE | When |
|---|---|---|
| 28000 | -919 | A password or SCRAM over plain TCP, before anything is sent; credentials the server refuses; a SCRAM server whose final signature is wrong, or an exchange that `binding: :require` cannot bind |
| 08004 | -919 | The server refuses the connection, as one past its SERVER.MAX_CONNECTIONS |
| 08006 | -919 | A server that cannot be reached, a failed TLS handshake, a wait past its timeout, a reply too long or malformed, a closed connection |
| TB910 | -910 | A channel binding not among `:prefer`, `:disable` and `:require` |

## EXAMPLES

```ruby
cache = Turborel::Client::KeyCache.new
2.times do
  conn = Turborel::Client.connect_local("/run/turborel/socket", user: "ann",
                                      mechanism: Turborel::Client::Scram.new("ann's password", cache:))
  conn.terminate
end
p cache.lookups
```

```text
[1, 1]
```

## STANDARD

[PROTOCOL Opening a connection], [PROTOCOL Mechanisms], [PROTOCOL
Capabilities], [PROTOCOL Cancel 'Z'] and [PROTOCOL Terminate 'X'] of
[The Native Protocol](https://github.com/turborel/turborel/blob/main/doc/client/05-protocol.md);
[CLIENT Connecting], [CLIENT Timeouts], [CLIENT What a connection asks
for], [CLIENT What the server tells] and [CLIENT The SCRAM key cache] of
[The Client Library](https://github.com/turborel/turborel/blob/main/doc/client/02-library.md)
and
[Settings, Pipelines and Pools](https://github.com/turborel/turborel/blob/main/doc/client/02-library-connections.md).

## SEE ALSO

[Connecting](../user/02-connecting.md), [Errors](30-errors.md),
[Values](23-values.md)
