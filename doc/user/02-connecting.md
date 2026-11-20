# Connecting

[Contents](README.md)

A program connects by the plain API's `Turborel.connect`, by settings,
or through the low-level client, `Turborel::Client`, naming where the
server is and who it connects as. Each gives the same connection.

## By the plain API

`Turborel.connect(uri, **settings)` connects as a `turborel://` URI
says, its settings by name laid over the URI's, then over those of the
service file, the environment and the defaults, as
[Settings](09-settings.md) tells; or as a `Turborel::Client::Settings`
it is given. It gives a `Turborel::Connection`, whose `client` is the
low-level client's connection beneath it.

```ruby
conn = Turborel.connect("turborel://127.0.0.1:7422/?tls_mode=disable", user: "bob", application_name: "reports")
puts conn.client.authorization
conn.close
```

```text
BOB
```

The rest of this chapter tells the low-level client's way, which the
plain API's rests on.

## Where the server is

A `Target` says where the server is and how it is reached:

- `Targets.tcp(host, port)`, over TCP, port 7422 unless another is
  given;
- `Targets.local(path)`, over a Unix socket at `path`, or on Windows the
  named pipe of that name, as `\\.\pipe\turborel`;
- `Targets.tls(host, port, server_name:, context:)`, over TLS on the TCP
  port, the server's certificate checked against `server_name` and
  trusted as `context` says.

`Client.connect_to(target, user:, mechanism:)` connects to a target;
`Client.connect(host, port, user:, mechanism:)` and
`Client.connect_local(path, user:, mechanism:)` are its short forms.

```ruby
require "turborel"

conn = Turborel::Client.connect("127.0.0.1", 7422, user: "ann", mechanism: Turborel::Client::Trust.new)
puts "#{conn.server}, as #{conn.authorization}"
conn.terminate
```

```text
turborel 0.0.0 (alpha), as ANN
```

The user is read as an identifier, so `ann` connects as ANN.

## Proving who connects

The mechanism proves the user:

| Mechanism | Proves the user by | Over |
|---|---|---|
| `Scram.new(password)` | SCRAM-SHA-256: the password never travels, and the server must prove it knows the user's verifier | TLS, a Unix socket or a named pipe |
| `Password.new(password)` | the password, sent whole | TLS, a Unix socket or a named pipe |
| `Certificate.new` | the certificate the TLS context presents, its common name the user's | TLS |
| `Trust.new` | nothing: the server trusts a client of its own machine, where its SERVER.TRUST_LOCAL is ON | anything |

A password, or SCRAM, is refused over plain TCP before anything is sent,
SQLSTATE 28000, as the server would refuse it. SCRAM goes over plain TCP
only where the program asks, `Scram.new(password, clear: true)`, for a
server whose SERVER.SCRAM_WITHOUT_TLS is ON.

Over TLS, SCRAM binds its exchange to the connection, so a server in the
middle cannot relay it: over TLS 1.3 by `tls-exporter`, over TLS 1.2 by
the hash of the certificate the server presented. `binding: :require`
refuses an exchange that cannot be bound; `binding: :disable` binds
nothing.

```ruby
context = Turborel::Client::TLS.context(roots: "/etc/turborel/ca.pem")
target = Turborel::Client::Targets.tls("db.example", 7422, server_name: "db.example", context:)
conn = Turborel::Client.connect_to(target, user: "ann", mechanism: Turborel::Client::Scram.new("ann's password"))
```

A wrong user or password is refused, SQLSTATE 28000:

```text
Turborel::Error: the user or the password is wrong
```

## TLS

`TLS.context` makes what a TLS connection trusts: the certificate
authorities of the PEM file `roots:`, the platform's if `platform: true`
(OpenSSL's: those of the files SSL_CERT_FILE and SSL_CERT_DIR name,
where either is set, else of its own default file and directory, where
one must be), or both; and, for the mechanism `certificate`, the
certificate chain of the PEM file `certificate:` and the private key of
the PEM file `key:`, both named. It speaks TLS 1.2 and 1.3 alone, as
turborel-client does. A server whose certificate is not trusted, or not
of the name connected to, fails the handshake, SQLSTATE 08006.

## Timeouts

`Timeouts.new(connect:, read:)`, in seconds, says how long a connection
waits: `connect` to connect, to begin TLS and for each step of the
login, 30 seconds by default; `read` for each read and write after, no
limit by default, as a statement may run as long as it must. A
connection's `read_timeout=` changes it. A wait that runs out loses the
connection, SQLSTATE 08006, saying the server did not answer in time. A
named pipe is bounded only as it is opened. A reply longer than the
connection's `max_body`, 16 MiB unless the program sets it, loses the
connection too.

## What is asked for, and told

A connection asks for every capability but compression unless its
`offer:` says otherwise: `Offers.none`, the protocol's first form;
`Offers.compressed(offer)`, compression too; `Offers.attribute(offer,
name, value)`, a connection attribute, the one named `application` the
program's name. `granted` gives what the server granted. The server
tells the session's settings as it begins: `setting(name)` gives one as
the server last told it, with no round trip, and `settings` all of them,
AUTHORIZATION, SCHEMA, READ_ONLY, SERVER_VERSION, SERVER_READ_ONLY,
CATALOG and OWNER among them.

## Ending

`terminate` ends the session, its transaction as SESSION.COMMIT_AT_END
says, and waits for the server to close, at most the read timeout, else
60 seconds; a commit that fails then raises its failure. `canceller`
gives what cancels the statement a connection runs, from another thread,
over a connection of its own; its `cancel` gives up after 10 seconds, or
a limit of the program's.
