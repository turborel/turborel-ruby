# Settings

[Contents](README.md)

A program that runs in more than one place reads where its servers are,
and as whom to connect, from outside itself. `Turborel::Client::Settings`
says where the servers are, as whom to connect and how; its `connect`
connects as it says, and gives a connection like `connect_to`'s.

## Connecting by settings

```ruby
settings = Turborel::Client::Settings.from_uri("turborel://ann@127.0.0.1:7422/?tls_mode=disable")
conn = settings.connect
puts "#{conn.server}, as #{conn.authorization}"
conn.terminate
```

```text
turborel 0.0.0 (alpha), as ANN
```

A password the settings give is proved by SCRAM-SHA-256; with no
password, the user is proved by the client's certificate if one is
named, else trusted as a local client. A secret mechanism is refused
over plain TCP before anything is sent, SQLSTATE 28000. Every connection
the same settings make shares one SCRAM key cache, so a reconnection
skips the key's derivation.

## Where settings come from

Each setting has a name, the same in the program's options, a URI's
query and a service file; [Appendix C](../appendix/c-settings.md) lists
them, each with its default. Settings come in layers, each setting taken
from the first layer that has it:

1. the program's own, an `Options` it fills or a connection URI;
2. the section of the service file the program or the environment names;
3. the environment's variables, TURBOREL_HOST and the rest;
4. the defaults.

A variable set but empty gives nothing. `Settings.resolve(options)`
reads the environment's variables from ENV, or through a block the
program gives, as a test does.

```ruby
options = Turborel::Client::Options.new("host" => "db1:7000,db2", "user" => "ann", "target" => "read-write")
env = { "TURBOREL_PORT" => "7500", "TURBOREL_TLS_MODE" => "verify-full" }
settings = Turborel::Client::Settings.resolve(options) { |name| env[name] }
p settings.hosts.map { |host| [host.name, host.port] }
p [settings.user, settings.target, settings.tls_mode]
```

```text
[["db1", 7000], ["db2", 7500]]
["ann", :read_write, :verify_full]
```

A setting that cannot be read, a service file that cannot be read or has
no section of the name, and settings that name no user are refused with
SQLSTATE 08001. `application_name` is sent as the connection attribute
`application`.

## The connection URI

```text
turborel://[<user>[:<password>]@][<host>[:<port>][,<host>[:<port>]]...][/][?<setting>=<value>[&<setting>=<value>]...]
```

Its parts are percent-encoded, so `p%40ss` is the password `p@ss` and
`%2Frun%2Fturborel.sock` a Unix socket; an IPv6 address is written in
brackets. A server serves one database, so the URI names none and has
no path. A URI of another scheme, of a path, of a setting not in the
table or of a pair without `=` is refused, SQLSTATE 08001.

## The service file and the password file

A service file, `~/.turborel_service.conf` unless `service_file` names
another, holds sections, each `[name]` on a line of its own, then lines
`setting = value`; `#` begins a comment, and blank lines are skipped. A
section cannot set `service` or `service_file`, and a malformed line is
refused, its file and line named.

```text
[production]
host = db1.example,db2.example
user = ann
tls_mode = verify-full
tls_roots = /etc/turborel/ca.pem
target = read-write
```

A password the settings do not give is looked up in the password file,
`~/.turborel_pass` unless `passfile` names another, by the server and
the user of each connection. Each line is `host:port:user:password`; a
field `*` matches anything; `\` takes the character after it as it is,
so `\:` is a colon in a field and `\*` a star; `#` begins a comment.
The first line that matches is taken; a Unix socket is matched by its
path and the default port. The file is read only if it is a regular
file, or a link to one; its owner answers for keeping it private.

## Several servers

`host` may name several servers. They are tried in the order given, or,
with `load_balance=random`, in an order drawn at random for each
connection. A name is tried at each address it resolves to, each step
within the connect timeout. A server that cannot be reached, refuses
the user, or is not of the role asked is passed for the next. With none
kept, the failure names each address and why, SQLSTATE 08001, or 28000
if the last refused the user.

`target=read-write` keeps a server that takes changes, a server alone or
its group's primary; `target=read-only` keeps a replica following its
group. The server tells each session whether it takes changes, as its
status SERVER_READ_ONLY; of one that does not, the role is read from
INFORMATION_SCHEMA.REPLICAS. `Turborel::Client::Role.of(connection)`
gives the role a connection's session sees.

```ruby
settings = Turborel::Client::Settings.from_uri("turborel://ann@127.0.0.1:1,127.0.0.1:2/?tls_mode=disable")
begin
  settings.connect
rescue Turborel::Error => e
  puts e.sqlstate, e.message.split(": ").first
end
```

```text
08001
no server was kept
```

## TLS by mode

`tls_mode` says how a connection over TCP uses TLS; a Unix socket or a
named pipe uses none.

| Mode | TLS | The server's certificate |
|---|---|---|
| `disable` | Never | |
| `prefer` | If the server takes it, else plain TCP | Not checked |
| `require` | Always | Not checked |
| `verify-ca` | Always | Signed by an authority trusted |
| `verify-full` | Always | Signed by an authority trusted, and of the server's name |

`verify-ca` and `verify-full` need the authorities trusted: `tls_roots`,
`tls_system_roots`, or both. The name checked is `server_name`, else the
host's. Under `prefer`, a server whose TLS handshake fails is connected
to again over plain TCP; one that cannot be reached is not tried twice.

`channel_binding` says whether SCRAM binds its exchange to the TLS
connection carrying it: `prefer` binds where the connection has a
binding, `disable` binds nothing, and `require` refuses, before any
proof, settings whose mechanism binds nothing or a connection not over
TLS, SQLSTATE 28000.
