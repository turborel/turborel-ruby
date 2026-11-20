<p align="center">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="artwork/turborel-logo-white.svg">
      <img src="artwork/turborel-logo.svg" alt="turborel" width="360">
    </picture>
</p>

> turborel-ruby is in alpha, meaning, version 0.0.0, as turborel is.
> Anything may change from one build to the next, its API and the
> protocol alike. See [VERSIONING.md](VERSIONING.md). Its version is
> the turborel release it is made for: the alpha speaks protocol
> version 1.

turborel-ruby is the Ruby driver for
[Turborel](https://github.com/turborel/turborel), a relational database
system. It speaks turborel's native protocol itself, in Ruby alone, with
no native extension and no other client library beneath it, so it runs
wherever Ruby does, on Linux, macOS and Windows.

It is built to match turborel-client, turborel's own client library,
feature for feature: TCP, Unix sockets and Windows named pipes, TLS,
SCRAM-SHA-256 and SCRAM-SHA-256-PLUS, prepared statements and cursors,
large objects, bulk copy, settings from a URI, the environment and
service and password files, several servers, pipelines and pools. Over
those come a plain API in the manner of the pg gem, and an ActiveRecord
adapter for Rails 8.1 and later. [CONFORMANCE.md](CONFORMANCE.md) shows
what is done, row by row, and [TODO.md](TODO.md) what is left. So far it
holds the protocol's frame header and its tests.

## What it needs

Ruby 3.3 or later: 3.3, 3.4 and 4.0 are tested, on Linux, macOS and
Windows. It needs no gem but Ruby's own: openssl, zlib and socket, which
ship with Ruby, and bigdecimal, a gem bundled with Ruby that the gemspec
declares ([RULES.md](RULES.md) D3, D4).

## Installing

The gem is not yet published to RubyGems; it will be once every turborel
driver is done ([VERSIONING.md](VERSIONING.md)). Until then, build it
from source:

```
git clone https://github.com/turborel/turborel-ruby.git
cd turborel-ruby
bundle config set --local path vendor/bundle
bundle install
bundle exec rake verify      # every check a change must pass
bundle exec rake build       # the gem, in pkg/
gem install pkg/turborel-0.0.0.gem
```

## A first query

This is what the plain API will be once it is built (milestone M7 of
[TODO.md](TODO.md)). None of it runs yet.

```ruby
require "turborel"

conn = Turborel.connect("turborel://ann@db.example/?tls_mode=verify-full")
conn.exec_params("SELECT ID, NAME FROM STAFF WHERE ID < ?", [3]) do |result|
  result.each { |row| puts "#{row['ID']} #{row['NAME']}" }
end
conn.transaction do
  conn.exec_params("UPDATE STAFF SET SALARY = SALARY * 1.1 WHERE ID = ?", [1])
end
conn.close
```

## Documents

- [doc/](doc/README.md): the manual, a User's Guide, an API Reference
  and appendices, its chapters written as the driver is built.
- [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md):
  contributing, and reporting an issue or a vulnerability.
- [RULES.md](RULES.md): how the driver is designed, written and verified.
- [CONFORMANCE.md](CONFORMANCE.md) and [TODO.md](TODO.md): what is done of
  the protocol and turborel-client, and what is open.
- [VERSIONING.md](VERSIONING.md): the version, and publishing.
- [LICENSE](LICENSE) and [TRADEMARK.md](TRADEMARK.md): the code is
  under the BSD-2-Clause Plus Patent License; the name Turborel and its
  logos are not, and TRADEMARK.md says how they may be used.
