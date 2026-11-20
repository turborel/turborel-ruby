<p align="center">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="artwork/turborel-logo-white.svg">
      <img src="artwork/turborel-logo.svg" alt="turborel" width="360">
    </picture>
</p>

> turborel-ruby is in alpha, meaning, version 0.0.0. Its version is the
> number of the Turborel release it is made for, and the alpha is made
> for Turborel 0.0.0, which speaks protocol version 1. Anything may
> change from one build to the next, API and behaviour alike. See
> [VERSIONING.md](VERSIONING.md). The latest Turborel alpha is built for
> Linux, macOS and Windows as the pre-release
> [nightly](https://github.com/turborel/turborel/releases/tag/nightly),
> and as the image `ghcr.io/turborel/turborel:nightly`.

turborel-ruby is the Ruby driver for
[Turborel](https://github.com/turborel/turborel), a relational database
system. It connects a Ruby program to a Turborel server,
`turboreld`, over Turborel's [native
protocol](https://github.com/turborel/turborel/blob/main/doc/client/05-protocol.md),
version 1, which it speaks itself, in Ruby alone, with no native extension.

Its standard interface is a plain API in the manner of the pg gem, and an ActiveRecord adapter for Rails 8.1 and later. Beneath it is a low-level
client built to do all that Turborel's own client library,
turborel-client, does: TCP, Unix sockets and Windows named pipes, TLS,
SCRAM-SHA-256 and SCRAM-SHA-256-PLUS, prepared statements and cursors,
large objects, bulk copy, import and export, settings from a URI, the
environment and service and password files, several servers, pipelines
and pools.

The driver is built in milestones, M0 to M8. Its low-level client
connects, logs in, runs statements, prepared statements and cursors,
reads and writes large objects, copies, imports and exports, and
connects by settings to one of several servers, pipelines requests,
pools connections and holds named connections as an SQL-agent, today;
the plain API and the ActiveRecord adapter come at M7.
[CONFORMANCE.md](CONFORMANCE.md) shows what is done, row by row, and
[TODO.md](TODO.md) what is open.

## Requirements

- Ruby 3.3 or later, on Linux, macOS or Windows ([RULES.md](RULES.md) D3).
- 3.3, 3.4 and 4.0 are tested; openssl, zlib, socket and bigdecimal, which ship with Ruby.
- A Turborel server of the same release, which speaks protocol version 1
  ([running the server](https://github.com/turborel/turborel/blob/main/doc/operator/02-turboreld.md)).

## Installing

No package is published yet. The driver's package, the gem `turborel`, goes to
RubyGems only once every Turborel driver is done, with the others
([VERSIONING.md](VERSIONING.md#publishing)). Until then, build the
driver from source:

```
git clone https://github.com/turborel/turborel-ruby.git
cd turborel-ruby
bundle config set --local path vendor/bundle
bundle install
bundle exec rake build
gem install pkg/turborel-0.0.0.gem
```

A program's Gemfile may name the clone instead:
`gem "turborel", path: "../turborel-ruby"`.

## A first query

This is what the standard API will be once milestone M7 builds it and
M8's audit checks it. None of it runs yet, and its names may change
until then.

```ruby
require "turborel"

conn = Turborel.connect("turborel://ann@db.example/?tls_mode=verify-full")
conn.exec_params("SELECT ID, NAME FROM STAFF WHERE ID < ?", [3]) do |result|
  result.each { |row| puts "#{row["ID"]} #{row["NAME"]}" }
end
conn.close
```

## The manual

[doc/](doc/README.md) is the manual: a User's Guide, an API Reference
and Appendices, published at
https://turborel.com/docs/drivers/ruby/. Each
chapter is written as the milestone that fills it lands. The SQL a
program sends, and the server, are described in Turborel's own manual,
[The Turborel Documentation Set](https://github.com/turborel/turborel/blob/main/doc/README.md).
[VERSIONING.md](VERSIONING.md) tells how the driver's releases are
numbered and published.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before making a change: how a
change is made, its commit message, pull requests and issues. Every
change passes `bundle exec rake verify`. [RULES.md](RULES.md) says how the
driver is designed, written and verified,
[CONFORMANCE.md](CONFORMANCE.md) is the parity matrix every Turborel
driver keeps, and [TODO.md](TODO.md) lists open work.

## Security

Report a vulnerability privately, never in a public issue, as
[SECURITY.md](SECURITY.md) says.

## License and trademark

The code is under the BSD-2-Clause Plus Patent License, in
[LICENSE](LICENSE). The name Turborel and its logos are not:
[TRADEMARK.md](TRADEMARK.md) says how they may be used.
