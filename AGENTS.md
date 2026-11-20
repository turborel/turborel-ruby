# Guide for coding agents

How to work on turborel-ruby as a coding agent, with any tool. If this file
disagrees with [RULES.md](RULES.md) or [CONTRIBUTING.md](CONTRIBUTING.md),
follow those.

turborel-ruby is the Ruby driver for Turborel, a relational
database system. It speaks Turborel's native protocol, version 1,
itself, in Ruby alone, with no native extension, and is built to do all turborel-client does. See
[README.md](README.md).

## Before you change anything

Read RULES.md §3 (code), §4 (tests), §6 (process) and the decisions for
your area. Read CONTRIBUTING.md for how a change is made and the extra
checks for changes that touch the protocol. Read the section of the
protocol, or of the client documents, that your change implements, and
the rows of CONFORMANCE.md it marks done.

## Build and check

Every change must pass `bundle exec rake verify` and `bundle exec rake coverage`
before it is handed back.

```
bundle config set --local path vendor/bundle   # gems in the clone, never system-wide
bundle install                                 # the tools Gemfile.lock pins
bundle exec rake install_hooks                 # run verify before each commit (once per clone)
bundle exec rake verify                        # every check a change must pass
bundle exec rake coverage                      # the tests under SimpleCov, held to the floor
bundle exec rake rubocop                       # lint and format; `bundle exec rubocop -a` fixes the format
bundle exec rake rules                         # lengths, printing, open-work markers, citations, the manual
bundle exec rake steep                         # types: lib/ against sig/
bundle exec rake rbs                           # the signatures themselves
bundle exec rake doc                           # the API reference, nothing undocumented
bundle exec rake test                          # the tests alone
bundle exec ruby -Ilib -Itest test/turborel/protocol/frame_test.rb
                                               # one test file alone
bundle exec rake build                         # the gem, in pkg/
```

`bundle exec rake verify` stops at the first failure (RULES.md D4). CI runs it
on Linux, macOS and Windows, on each supported runtime, and coverage on
Linux. The coverage floor only rises (D7, R-COV-2).

Project automation is the language's own tooling, never shell scripts
(R-PROC-5).

## Where things are

| Path | What |
|---|---|
| `turborel.gemspec`, `Gemfile`, `Gemfile.lock` | the gem, and the development tools locked (D9, D10) |
| `Rakefile`, `rakelib/` | the checks tool: `verify` and each check, `coverage`, `build` (D4) |
| `rakelib/headings/` | the headings of Turborel's three documents tests cite, at 045e42a9 (D6) |
| `Steepfile`, `.rubocop.yml`, `.simplecov`, `.yardopts` | the type checker, the linter and formatter, coverage, the API reference |
| `lib/turborel.rb` | the gem's root module |
| `lib/turborel/version.rb` | `Turborel::VERSION` (D5) |
| `lib/turborel/error.rb`, `failure.rb` | `Turborel::Error`, every failure, and the `Failure` and `Diagnostics` it carries (R-ERR-1) |
| `lib/turborel/values.rb` | the value classes a value of the protocol is read into and written from: `Datetime`, `Interval`, `DecFloat`, `Lob` and the rest, and `DataType`, `Column` and `Parameter` |
| `lib/turborel/protocol/` | the `codec` layer, with no I/O (D1): `reader.rb` and `writer.rb`, the fields; `frame.rb` and `compression.rb`, frames; `tail.rb`; `types.rb`; `values.rb`, `value_reader.rb` and `value_writer.rb`; `json_binary.rb` and `json_decoder.rb`, JSON's binary tree; `fields.rb`, the composite fields; `requests.rb` and `replies.rb`, every message |
| `lib/turborel/client.rb`, `lib/turborel/client/` | the low-level client: the `transport` layer (`target.rb`, `transport.rb`, `stream.rb`, `timeouts.rb`), `auth` and `tls` (`mechanisms.rb`, `scram.rb`, `key_cache.rb`, `tls.rb`), and the `session` (`connection.rb`, `wire.rb`, `statements.rb`, `session.rb`, `outcomes.rb`, `offer.rb`, `canceller.rb`), its large objects, copies and exports (`lobs.rb`, `lob_streams.rb`, `copy.rb`, `export.rb`), connecting by settings (`settings.rb`, `settings/`, `failover.rb`), and throughput (`pipeline.rb`, `pool.rb`, `agent.rb`, `connection_statement.rb`) |
| `lib/turborel/api/` | the standard API's plain API (D2): `Turborel.connect` and `Turborel::Connection` (`connection.rb`), `Turborel::Result` (`result.rb`) |
| `lib/active_record/connection_adapters/turborel_adapter.rb`, `turborel/`, `lib/turborel/registration.rb` | the ActiveRecord adapter (D2, D16): the adapter, its quoting, statements, schema statements, values, defaults, failures and Arel visitor; its registration as `turborel` |
| `lib/turborel/import.rb`, `lib/turborel/import/` | imports: the source's records, delimited text, SQL names, string assignment, the run by INSERT or by copy |
| `lib/turborel/text.rb`, `lib/turborel/text/` | values written as Turborel shows them, and a JSON value's text |
| `lib/turborel/xml/` | an XML value's nodes, parsed from its text |
| `sig/` | RBS signatures, a file for each of `lib/` but the ActiveRecord adapter's (D11, D16) |
| `test/` | minitest, a `*_test.rb` for each file of `lib/`, and `test_helper.rb` (D13); `test/support/` the fake server unit tests script; `test/server/` the live tests' server set-up (R-TEST-8); `test/active_record/` the adapter's; `test/fixtures/` Turborel's sample frames, copied at 045e42a9 (D17) |
| `doc/` | the manual |

The protocol is Turborel's `doc/client/05-protocol.md`, the client's
features `doc/client/02-library.md` and `02-library-connections.md`, and
the reference code `protocol/src/` and `client/src/`, all in
[turborel](https://github.com/turborel/turborel). Where the page and the
code differ, the code is right; CONFORMANCE.md names each such place.

## Rules that are broken most often

`bundle exec rake verify` treats every warning as an error (R-LINT-1). RULES.md
§3 and §4 have the full list.

- Every failure is the driver's error, with its SQLCODE and SQLSTATE
  (R-ERR-1, R-ERR-2). No error of the language or a library beneath it
  reaches a program; catch it, and give the driver's, keeping the cause
  (R-ERR-3).
- No printing, and no ending the process, in library code (R-STYLE-3,
  R-ERR-1).
- Check every length or count a server sends against its bound before
  reading or reserving for it (R-SAFE-1).
- No secret in a log, a failure's message or an object's display form
  (R-SAFE-4).
- Integers of the protocol are read and written at their width,
  little-endian; exact numbers never pass through a float (R-NUM).
- Keep functions to 50 lines of code and 5 parameters, and files to 600
  lines (R-SIZE).
- No magic numbers or strings: protocol tags, kinds, capability, status
  and mechanism names are named constants, defined once (R-CONST).
- Every public item has a doc comment (R-DOC-1). Comments say why
  (R-DOC-2). No `TODO` comments or commented-out code (R-DOC-5).
- A silenced warning names its rule and says why (R-LINT-3).
- No dependency without a decision in RULES.md (R-DEP-1).
- Code of one platform is chosen by the platform and refused elsewhere
  with the driver's error (R-PLAT-2).
- Every method of `lib/` but the ActiveRecord adapter's (D16) has its
  signature in `sig/`, and Steep passes
  with its strict diagnostics (R-TYPE-1, D11). A cast, `_ = ...`, says
  in a comment why the value has the type it is given (R-TYPE-2).
- No `# rubocop:disable`: a deviation is kept in `.rubocop.yml`, with
  its rule and its reason (R-LINT-3, D8).

## Tests

Every test cites what it verifies, by the comment above it, beginning `Verifies:`, beginning with a
tag (R-TRACE-1, D6):

- `[PROTOCOL <heading>]`, a section of 05-protocol.md, as
  `[PROTOCOL Frames]`;
- `[CLIENT <heading>]`, a section of 02-library.md or
  02-library-connections.md, as `[CLIENT Pipelines]`;
- `[DESIGN] D<n>`, a decision of RULES.md;
- `[TOOL] R-<id>`, a rule the checks tool holds.

The checks tool refuses a heading, decision or rule that is not there
(R-TRACE-2). Tests are deterministic, with no clock, randomness or
network beyond loopback (R-TEST-5). A shared fixture is written once
(R-TEST-7). A fixed defect gets a regression test that fails without the
fix (R-TEST-6). A live test runs its own server on its own port and data
directory, and stops it.

## Citing the spec

Check every citation against the document before writing it, by its
heading as printed. Never cite from memory. Code never cites TODO.md.

## Documents

A finished feature updates these in the same change:

- RULES.md, if it made a decision, including the row in §1's table;
- CONFORMANCE.md, each row it implements (R-TRACE-4), marked done only
  where its code exists and its tests pass;
- TODO.md, which only holds open work;
- [doc/](doc/README.md), for anything a program sees (R-DOC-7), every
  example run: each page keeps its `# Title` and its
  `[Contents](README.md)` line, links to this repository's files are
  relative (the docs site points those outside `doc/` at GitHub, at the
  same tag), links to Turborel's manual are GitHub addresses,
  `user/01-installing.md` keeps its name, and `doc/` holds no images;
- README.md, if what the driver is or needs changes.

No document gives timings or speedups; numbers go in a commit message.

## Commits

- Commit only when the maintainer asks, and never push without approval.
- Follow CONTRIBUTING.md's form, with one logical change per commit.
- Add no AI or agent attribution to a commit, a pull request, a file or
  the package's metadata. That means no `Co-Authored-By` for an agent,
  no "Generated with" and no `Signed-off-by`.
- Stage with an explicit path list, `git add -- <path> ...`. Never use
  `git add -A` or `git add .` on the whole tree.
- Never stage scratch files, or a live test's data directory.
- Code compiled for one platform only can't be verified locally on
  another. Say so when handing it back (R-PLAT-4).
