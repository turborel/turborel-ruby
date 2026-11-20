# Installing

[Contents](README.md)

This chapter tells what the driver needs, how a program takes the gem
`turborel` in, and how it connects for the first time, with the
standard API: the plain API, of connections, results and prepared
statements, or the
ActiveRecord adapter.

## What the driver needs

- Ruby 3.3 or later, on Linux, macOS or Windows; 3.3, 3.4 and 4.0 are
  tested.
- No gem but Ruby's own: openssl, zlib and socket, which ship with
  Ruby, and bigdecimal, which the gem declares, as it is no longer a
  default gem from Ruby 3.4.
- A Turborel server of the same release, which speaks protocol
  version 1
  ([running the server](https://github.com/turborel/turborel/blob/main/doc/operator/02-turboreld.md)).
- For the ActiveRecord adapter, ActiveRecord 8.1 or later, which a Rails
  application has already. The gem does not depend on it, and a program
  that does not use the adapter never loads it.

## Taking the gem in

No package is published until every Turborel driver is done
([VERSIONING.md](../../VERSIONING.md#publishing)); until then the driver
is built from its source:

```
git clone https://github.com/turborel/turborel-ruby.git
cd turborel-ruby
bundle config set --local path vendor/bundle
bundle install
bundle exec rake build
gem install pkg/turborel-0.0.0.gem
```

or a program's Gemfile names the clone, as
`gem "turborel", path: "../turborel-ruby"`.

## A first connection

`require "turborel"` loads the driver. `Turborel.connect` connects by a
`turborel://` URI, by settings by name, or both, and gives a
`Turborel::Connection`; `exec` runs a statement and `exec_params` one
with `?` parameters, each giving a `Turborel::Result`. As Turborel's
are, a connection's statements are in a transaction until COMMIT or
ROLLBACK.

```ruby
require "turborel"

conn = Turborel.connect("turborel://ann@127.0.0.1:7422/?tls_mode=disable")
conn.exec("CREATE TABLE GREETING (ID INTEGER PRIMARY KEY, WORDS VARCHAR(20))")
conn.exec_params("INSERT INTO GREETING VALUES (?, ?)", [1, "hello, Turborel"])
conn.exec("COMMIT")
conn.exec("SELECT ID, WORDS FROM GREETING").each { |row| puts "#{row["ID"]}: #{row["WORDS"]}" }
conn.close
```

```text
1: hello, Turborel
```

[Connecting](02-connecting.md) tells every way to connect, and the
low-level client, `Turborel::Client`, beneath the plain API, which has
every feature of Turborel's own client library.

## In a Rails application

The Gemfile names the gem, and `config/database.yml` the adapter
`turborel`, with the connection's settings:

```yaml
development:
  adapter: turborel
  host: db.example
  username: ann
  password: <%= ENV["TURBOREL_PASSWORD"] %>
  tls_mode: verify-full
```

or a URL, `url: turborel://ann@db.example/`. Requiring the gem registers
the adapter, as Bundler requires it in a Rails application; a program
outside Rails requires `active_record/connection_adapters/turborel_adapter`
itself. [The ActiveRecord Adapter](../client/03-api-active-record.md)
tells what it does.
