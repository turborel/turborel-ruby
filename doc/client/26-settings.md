# Settings

[Contents](README.md)

## NAME

`Turborel::Client::Settings`, `Options`, `Host`, `TlsFiles` and `Role`:
connection settings from outside the program, and connecting by them to
one of several servers.

## SYNOPSIS

```ruby
Turborel::Client::Settings.from_uri(uri) { |variable| ... }       # => Settings
Turborel::Client::Settings.resolve(options = Options.new) { |variable| ... } # => Settings
Turborel::Client::Settings.service(file, name)                    # => Options
settings.connect                                                  # => Connection
settings.password_for(host)                                       # => String, or nil
settings.hosts  settings.user  settings.password  settings.tls_mode  settings.channel_binding
settings.application_name  settings.connect_timeout  settings.passfile  settings.target
settings.load_balance  settings.tls  settings.key_cache

Turborel::Client::Options.new(hash = {})   options.set(name, value)   options[name]   options.over(lower)
Turborel::Client::Options.environment { |variable| ... }          # => Options
Turborel::Client::Host.tcp(name, port) | .local(path)             # name, port, path, local?
Turborel::Client::TlsFiles                 # roots, system_roots, certificate, key, server_name
Turborel::Client::Role.of(connection)      # => :read_write, :read_only or :unknown
```

## DESCRIPTION

`resolve` lays the program's `Options` over the section of the service
file they or the environment name, over the environment's variables,
read from ENV or by the block, over the defaults; `from_uri` reads the
program's from a `turborel://` URI. Settings are read into Ruby values:
`tls_mode` as `:disable`, `:prefer`, `:require`, `:verify_ca` or
`:verify_full`; `channel_binding` as `:disable`, `:prefer` or
`:require`; `target` as `:any`, `:read_write` or `:read_only`;
`load_balance` as `:disable` or `:random`; `connect_timeout` in whole
seconds, `nil` for no limit; `hosts` as `Host`s, each of its port, or of
the port of its place in `port`, or of the one port given, or 7422.
`inspect` never shows the password.

`connect` tries each host in order, or in a random order under
`load_balance=random`, at each address its name resolves to, over TLS as
`tls_mode` says, the user proved by SCRAM-SHA-256 of the password the
settings or the password file give, else by the certificate named, else
trusted, and keeps the first server of the role `target` asks; its
connections share the settings' `key_cache`. `password_for` gives the
password proved at a host. `Role.of` gives the role a connection's
session sees: from its status SERVER_READ_ONLY, else from
INFORMATION_SCHEMA.REPLICAS, asked as its own transaction.

## ERRORS

| SQLSTATE | SQLCODE | When |
|---|---|---|
| 08001 | -919 | A setting that cannot be read; a URI that is not one; a service file that cannot be read, has a malformed line, or no section of the name; no user named; a server not of the role asked; several servers, none kept, each named with why |
| 28000 | -919 | A password over plain TCP, before it is sent; channel binding required by settings that cannot bind, before any proof; the last of several servers refusing the user |
| 08006 | -919 | One server, that cannot be reached or whose TLS handshake fails; a verifying TLS mode with no authority trusted; a client certificate named without its key |

## EXAMPLES

```ruby
options = Turborel::Client::Options.new("user" => "ann", "host" => "[::1]:7001,/run/turborel.sock")
settings = Turborel::Client::Settings.resolve(options) { nil }
p settings.hosts.map { |host| host.local? ? host.path : [host.name, host.port] }
p settings
```

```text
[["::1", 7001], "/run/turborel.sock"]
#<Turborel::Client::Settings hosts=[#<data Turborel::Client::Host name="::1", port=7001, path=nil>, #<data Turborel::Client::Host name=nil, port=nil, path="/run/turborel.sock">] user="ann" tls_mode=prefer target=any>
```

## STANDARD

[CLIENT Connecting by settings], [CLIENT Where settings come from],
[CLIENT The connection URI], [CLIENT The service file], [CLIENT The
password file], [CLIENT Several servers], [CLIENT TLS by mode] and
[CLIENT The SCRAM key cache] of [Settings, Pipelines and
Pools](https://github.com/turborel/turborel/blob/main/doc/client/02-library-connections.md).

## SEE ALSO

[Settings](../user/09-settings.md), [Appendix C](../appendix/c-settings.md),
[Connections](21-connections.md)
