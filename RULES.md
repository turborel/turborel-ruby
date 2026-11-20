# turborel-ruby rules

How turborel-ruby, the Ruby driver for turborel, is designed, written and
verified. Every change follows these rules; `bundle exec rake verify`
checks those a tool can check, and review checks the rest. They are
modelled on turborel's own RULES.md, adapted to Ruby.

Rules (R-…) say how code and tests are written. **shall** is mandatory,
and a departure needs a recorded deviation (§6). **should** is expected, and
a reviewer may accept a reasoned exception.

Decisions (D1…) record how the driver is built and why. Change one only by
changing this file in a reviewed commit. A decision says what was chosen and
why, and the file it names holds the mechanism.

Cite both by ID in code, tests, reviews and commit messages, as in
`RULES.md D4` or `R-ERR-1`.

Before changing code, read §3 (code rules), §4 (test rules) and the
decisions covering your area. What the driver implements, against the
protocol and turborel-client, is in [CONFORMANCE.md](CONFORMANCE.md), and
open work is in [TODO.md](TODO.md).

[1 Decisions](#1-decisions) · [2 Layout](#2-project-layout) ·
[3 Code](#3-code-rules) · [4 Tests](#4-test-rules) ·
[5 Coverage](#5-coverage) · [6 Deviations](#6-deviations) ·
[7 Process](#7-process-and-tools) · [8 Platforms](#8-platforms) ·
[9 Ruby's conventions](#9-where-rubys-conventions-differ) ·
[10 References](#10-references)

---

## 1. Decisions

| # | Decision |
|---|---|
| **The driver** | |
| D1 | Native protocol 1, in Ruby alone, with no native core |
| D2 | A plain API in the manner of the pg gem, and an ActiveRecord adapter |
| D3 | Ruby 3.3 and later, each release Ruby itself still maintains |
| D4 | No runtime dependency but Ruby's own gems; bigdecimal declared |
| D12 | The driver's version is the turborel release it is made for |
| **Tooling and process** | |
| D5 | Development tools in the Gemfile, locked |
| D6 | Types in RBS, checked by Steep, strictly |
| D7 | `rake verify` runs in a pre-commit hook and in CI |
| D8 | RuboCop is the linter and the formatter |
| D9 | Tests are minitest, each citing what it verifies |
| D10 | Coverage by SimpleCov, with floors that only rise |
| D11 | The API reference is YARD's, with nothing undocumented |

### The driver

#### D1. Native protocol 1, in Ruby alone, with no native core

The driver speaks turborel's native protocol, version 1
(`doc/client/05-protocol.md` in turborel's repository), itself, in Ruby.
It has no C extension and wraps no other client library, so it installs
from RubyGems with no compiler, on every platform Ruby runs on, and every
line of it can be read and tested from Ruby. Where the protocol's page
and turborel-client's code differ, the code is right, and the difference
is reported to turborel.

The layers follow turborel-client's modules, so a reviewer can check one
against the other: the codec (`lib/turborel/protocol/`, no I/O), the
transport, authentication, the session, statements, large objects, bulk
copy, settings, and throughput (pipelines, pools, the SQL-agent). The
standard API (D2) is built over them.

#### D2. A plain API in the manner of the pg gem, and an ActiveRecord adapter

Ruby has no standard database interface of its own. What Ruby programs
know is the pg gem's: a connection, `exec` and `exec_params`, `prepare`
and `exec_prepared`, results read by row and by column, and transactions.
So the driver's plain API, under `require "turborel"`, takes that shape:
`Turborel::Connection`, `Turborel::Result` and the rest, its failures
`Turborel::Error` (R-ERR-1). It is a shape, not a copy: names and
behaviour follow turborel, not PostgreSQL, where they differ.

Rails is how most Ruby programs reach a database, so the driver also
ships an ActiveRecord adapter for Rails 8.1 and later, in this
repository, under its own require path,
`active_record/connection_adapters/turborel_adapter`, registered as the
adapter `turborel`. ActiveRecord is not a dependency of the gem (D4): a
program that uses the adapter has Rails already, and one that does not
never loads it. The adapter is built with the standard API, milestone M7.

#### D3. Ruby 3.3 and later, each release Ruby itself still maintains

The driver supports every Ruby release the Ruby core team still
maintains, and drops each as it reaches its end of life, as Ruby's own
gems do. In November 2026 those are 3.3 (in security maintenance, its end
of life expected on 2027-03-31), 3.4 and 4.0; 3.2 reached its end of life
on 2026-04-01. Rails 8.1, which the adapter targets (D2), needs Ruby 3.2,
so it sets no higher floor. `required_ruby_version` is `>= 3.3`, and CI
tests 3.3, 3.4 and 4.0. A new Ruby is added to CI as it is released, and
the floor rises in a commit of its own.

#### D4. No runtime dependency but Ruby's own gems; bigdecimal declared

The driver needs TLS, SHA-256 and HMAC, PBKDF2, zlib, sockets and a type
that holds every exact number the protocol carries (an `i128` of units
and a `u32` scale). Ruby has each: `openssl`, `zlib` and `socket`, which
ship with Ruby as default gems or its own extensions, and `bigdecimal`.
No other gem is a runtime dependency, so nothing outside Ruby's own
releases needs to be trusted or qualified.

`bigdecimal` was a default gem up to Ruby 3.3, and is a bundled gem from
3.4 (3.4 ships 3.1.8, 4.0 ships 4.0.1). A bundled gem is installed with
Ruby but, under Bundler, can be required only if it is declared. So the
gemspec declares `bigdecimal`, `>= 3.1` (Ruby 3.3's default is 3.1.5),
`< 5`. It is still Ruby's own gem, maintained by the Ruby core team.

A new runtime dependency needs a decision here (R-SAFE-2), and the
standard library comes first.

#### D12. The driver's version is the turborel release it is made for

The driver has no version scheme of its own. Its version is the number
of the turborel release it is made for, the same number as the server's,
and a turborel release and each driver's release share it. The alpha is
0.0.0, as turborel's is, and speaks protocol version 1.
[VERSIONING.md](VERSIONING.md) has the rest.

### Tooling and process

#### D5. Development tools in the Gemfile, locked

The tools a contributor needs are in the Gemfile's `development` group,
not in the gemspec, as Bundler's own gem template has it: rake, minitest,
RuboCop with its minitest, performance and rake plug-ins, rbs, Steep,
SimpleCov and YARD. Each is the Ruby community's standard tool for its
job and maintained as production software. `Gemfile.lock` is committed
(R-CM-2), with every platform CI runs on, so each run installs the same
versions, and Dependabot proposes updates to it.

Gems are installed into the clone, by `bundle config set --local path
vendor/bundle`, never system-wide.

#### D6. Types in RBS, checked by Steep, strictly

Every file in `lib/` has its signatures in `sig/`, in RBS, Ruby's own
type language. Steep checks `lib/` against them with its strict
diagnostics (`Steepfile`), and `rbs validate` checks the signatures
themselves. Steep, not rbs alone, because rbs checks only that the
signatures are well formed; Steep checks the code against them.

A Steep annotation that casts a value (`_ = ...`) says in a comment why
the value has the type it is given (R-DEV-2).

#### D7. `rake verify` runs in a pre-commit hook and in CI

`bundle exec rake verify` runs every check: RuboCop, the rules no linter
checks (`rake rules`), Steep, `rbs validate`, YARD and the tests. CI runs
it on Linux, macOS and Windows, on each supported Ruby (D3), and the
coverage job on Linux. `bundle exec rake install_hooks` points git at
`.githooks/`, whose `pre-commit` runs `rake verify`.

#### D8. RuboCop is the linter and the formatter

Ruby has no formatter apart from its linter in common use, so RuboCop's
layout cops are the formatter, and `rubocop -a` applies them. Its
configuration (`.rubocop.yml`) enables every new cop as it comes, and
some off by default: method documentation, explicit error classes, number
conversion, require order. Every offense fails `verify`.

#### D9. Tests are minitest, each citing what it verifies

Tests are minitest, the test framework that ships with Ruby, under
`test/`, one `*_test.rb` file per library file, run by `rake test`.
Minitest runs a file's tests in an order drawn from a seed it prints; the
order changes, the tests do not, so a test that depends on another fails
and the seed repeats it (R-TEST-3).

Each test's comment begins with `# Verifies:` and what it verifies
(R-TRACE-1).

#### D10. Coverage by SimpleCov, with floors that only rise

`rake coverage` runs the tests under SimpleCov, measuring the lines and
branches of `lib/`, and fails below its floors (`.simplecov`): 95 % of
lines and 90 % of branches. The floors are below 100 % because code of one
platform (named pipes, Unix sockets) runs only where its platform does,
and coverage is measured on Linux. They only rise (R-COV-2).

#### D11. The API reference is YARD's, with nothing undocumented

Documentation comments are YARD's, the format RubyGems' documentation
sites read. `rake doc` builds the reference into `doc/api/`, failing on
any warning or on any class, module, method or constant with no
documentation. Classes and modules internal to the driver are marked
`@api private` and left out of the reference.

---

## 2. Project layout

```
turborel.gemspec        the gem: name, version, license, files (D4, D12)
Gemfile, Gemfile.lock   development tools, locked (D5)
Rakefile                the checks, and `verify` (D7)
rakelib/                more tasks: `rules`, `doc`
Steepfile               the type check (D6)
.rubocop.yml            lint and format (D8)
.simplecov              coverage and its floors (D10)
.yardopts               the API reference (D11)
README.md               what the driver is; installing; a first query
RULES.md                this file
CONFORMANCE.md          the parity matrix: the protocol and turborel-client
TODO.md                 open work, by milestone
VERSIONING.md           the version, and how it is published
CONTRIBUTING.md         changes, commit messages, pull requests, issues
SECURITY.md             how to report a vulnerability
AGENTS.md               the guide for coding agents
CLAUDE.md               points Claude Code to AGENTS.md
.github/                CI (workflows/: verify, release, cla, labels,
                        triage, docs-site), issue forms, pull request
                        template, labels, Dependabot
.githooks/pre-commit    runs `rake verify` before each commit
lib/turborel.rb         the gem's root module
lib/turborel/           the driver, one concept per file
  protocol/             the codec, no I/O (D1)
sig/                    RBS signatures, a file for each in lib/ (D6)
test/                   minitest, a file for each in lib/ (D9)
  test_helper.rb        what every test requires first
doc/                    the manual (R-DOC-6), laid out as turborel's,
                        which turborel.com's docs site reads
  README.md             the documentation set
  user/                 Volume I, the User's Guide
  client/               Volume II, the API Reference
  appendix/             types, errors, settings, versions
artwork/                the logos
```

---

## 3. Code rules

### R-STYLE: formatting and idiom

| ID | Rule | Checked by |
|---|---|---|
| R-STYLE-1 | Code **shall** be formatted as RuboCop's layout cops say (D8). | `rake rubocop` |
| R-STYLE-2 | Code **shall** pass RuboCop as configured, every offense failing; a Ruby warning about `lib/` fails its test. | `rake rubocop`; `test_helper.rb` |
| R-STYLE-3 | Names **shall** follow Ruby's casing; code implementing a message or field of the protocol is named after it: `Hello`, `encode_header`. | review |
| R-STYLE-4 | Each file **shall** start with `# frozen_string_literal: true`. | `Style/FrozenStringLiteralComment` |
| R-STYLE-5 | Library code **shall not** print, exit, or open a debugger. | `rake rules` |
| R-STYLE-6 | Library code **shall not** reopen or patch a class it does not own, nor define a method at the top level. | review; `Style/TopLevelMethodDefinition` |

### R-SIZE: short methods and files

| ID | Rule | Checked by |
|---|---|---|
| R-SIZE-1 | A method **shall** have at most 50 lines. | `Metrics/MethodLength` |
| R-SIZE-2 | A source file **shall** have at most 600 lines; split by the protocol's sections or the driver's layers. | `rake rules` |
| R-SIZE-3 | A method **shall** take at most 5 parameters, keywords counted; else take an object or a hash of options. | `Metrics/ParameterLists` |
| R-SIZE-4 | A file **should** hold one concept, stated in its class's or module's documentation. | review |

### R-DOC: comments and documentation

| ID | Rule | Checked by |
|---|---|---|
| R-DOC-1 | Every class, module, method and constant **shall** have a YARD comment; a public method gives `@param`, `@return` and each `@raise`. | `rake doc`; `Style/Documentation`, `Style/DocumentationMethod` |
| R-DOC-2 | Comments **shall** say *why*: the rule implemented, the choice made, the invariant relied on. | review |
| R-DOC-3 | The API reference **shall** build without warnings. | `rake doc` |
| R-DOC-4 | Behaviour the protocol or turborel-client governs **shall** cite it by its section's heading: `[PROTOCOL Frames]` for `05-protocol.md`, `[CLIENT Pipelines]` for `02-library.md` or `02-library-connections.md`, whose headings are distinct. A choice of the driver's own cites `[DESIGN]` and its decision. | review; `rake rules` with `TURBOREL_DOC` |
| R-DOC-5 | No commented-out code, and no `TODO`, `FIXME`, `XXX` or `HACK` comments: open work goes in TODO.md, and code never cites TODO.md. | review; `rake rules` |
| R-DOC-6 | A change visible to a program **shall** update the manual, `doc/`, in the same commit, its examples run. | review |
| R-DOC-7 | The manual **shall** keep turborel's layout, which turborel.com's docs site reads: each chapter its `# Title`, then a line `[Contents](README.md)`; links between pages relative `.md` links. Every relative link in a document **shall** resolve to a file. | review; `rake rules` |

### R-CONST: no magic numbers or strings

| ID | Rule | Checked by |
|---|---|---|
| R-CONST-1 | Numeric literals other than `0` or `1` **shall** be named constants, documenting the value's source. | review |
| R-CONST-2 | The protocol's tags, kinds, capability names and status names, and strings matched or looked up, **shall** be named constants, defined once. Messages for people are not. | review |
| R-CONST-3 | Related constants **shall** live together, in the module of their concept. | review |
| R-CONST-4 | Tests may use literal fixtures; an expected value restating a constant **should** use it. | review |

### R-ERR: errors

| ID | Rule | Checked by |
|---|---|---|
| R-ERR-1 | Every failure the driver raises **shall** be a `Turborel::Error`, or a subclass, carrying SQLCODE, SQLSTATE and message, and the rest of the failure where known: the rule it cites, its position, whether a transaction is active, and its diagnostics. | review; tests |
| R-ERR-2 | An exception from Ruby or the system (`IOError`, `SystemCallError`, `OpenSSL::SSL::SSLError`, `Zlib::Error`, …) **shall** be rescued where it arises and raised as a `Turborel::Error`, the original as its `cause`. | review; tests |
| R-ERR-3 | Library code **shall not** call `exit`, `exit!` or `abort`, nor rescue `Exception`. | `rake rules`; `Lint/RescueException` |
| R-ERR-4 | A failure that loses the connection **shall** leave the connection closed and say so to every later call. | tests |
| R-ERR-5 | An error raised **shall** name its class; never a bare `raise "..."`. | `Style/ImplicitRuntimeError` |

### R-SAFE: resources and dependencies

| ID | Rule | Checked by |
|---|---|---|
| R-SAFE-1 | Nothing the server sends **shall** make the client hold memory without bound: every length and count read is checked against what remains or a named limit before it is used. | review; tests |
| R-SAFE-2 | Each runtime dependency **shall** have a §1 decision covering why, its version and its license, and be production-grade by its own claims; the standard library comes first (D4). | review |
| R-SAFE-3 | No `eval`, `instance_eval` of a string, `Marshal.load` or `send` of a name from outside. | review; `Security/Eval`, `Security/MarshalLoad` |
| R-SAFE-4 | A secret (a password, a SCRAM key, a cancel key) **shall not** appear in an error's message, an `inspect`, or a log. | review; tests |
| R-SAFE-5 | Library code **shall not** start a thread the program did not ask for. | review |

---

## 4. Test rules

### R-TEST: levels and layout

| ID | Rule | Checked by |
|---|---|---|
| R-TEST-1 | Tests **shall** be minitest, under `test/`, a `*_test.rb` for each file of `lib/`, each requiring `test_helper`. | review |
| R-TEST-2 | Tests **shall** derive from the protocol and turborel-client, not the code: normal cases, edges, and robustness cases with the exact SQLCODE and SQLSTATE expected. | review |
| R-TEST-3 | Tests **shall** be deterministic and independent: no clock, randomness beyond minitest's seeded order (D9), or network beyond loopback. | review |
| R-TEST-4 | A test's name **shall** say the behaviour checked. | review |
| R-TEST-5 | Every fixed defect **shall** get a regression test, failing without the fix, its comment saying so. | review |
| R-TEST-6 | A fixture or helper shared by test files **shall** be written once, in `test_helper.rb` or a file it requires. | review |
| R-TEST-7 | Live tests run against a turborel server on loopback, set up by the tests' own fixtures, and are skipped, saying why, where no server is given. | review |

### R-TRACE: traceability

| ID | Rule | Checked by |
|---|---|---|
| R-TRACE-1 | Every test **shall** have a comment whose first line begins `# Verifies:` and a tag: `[PROTOCOL <heading>]`, `[CLIENT <heading>]`, `[RFC <number> ...]`, or `[DESIGN]` and the decision. | `rake rules` |
| R-TRACE-2 | Every heading cited **shall** be a heading of the manual it names. `TURBOREL_DOC=<turborel>/doc/client rake rules` checks each one. | `rake rules`, with `TURBOREL_DOC` |
| R-TRACE-3 | CONFORMANCE.md **shall** change with the change that implements or changes a row of it. | review |

---

## 5. Coverage

| ID | Rule | Checked by |
|---|---|---|
| R-COV-1 | Coverage **shall** be measured by `rake coverage`, lines and branches of `lib/`. | `rake coverage` |
| R-COV-2 | Coverage **shall not** fall below the floors in `.simplecov`; a change raising it **should** raise them (D10). | `rake coverage`, in CI |
| R-COV-3 | Gaps are closed by tests derived from requirements, or by removing dead code; never by tests with no requirement. | review |

---

## 6. Deviations

| ID | Rule | Checked by |
|---|---|---|
| R-DEV-1 | RuboCop **shall not** be disabled in source; a deviation goes in `.rubocop.yml`, with a comment citing the rule and why. | `Style/DisableCopsWithinSourceCodeDirective` |
| R-DEV-2 | A Steep annotation that casts a value **shall** carry a comment saying why the value has that type (D6). | review |

---

## 7. Process and tools

| ID | Rule | Checked by |
|---|---|---|
| R-PROC-1 | `bundle exec rake verify` **shall** pass before every commit: RuboCop, the rules, Steep, `rbs validate`, YARD and every test. CI adds coverage. | pre-commit hook; CI |
| R-PROC-2 | Every change **shall** be reviewed against the checklist below. | review |
| R-PROC-3 | Commits **should** be small and single-purpose, in CONTRIBUTING.md's form (`area: summary`, then why), citing rules applied or changed. | review |
| R-PROC-4 | The gem **shall** be published only as VERSIONING.md says, by the owner. | review |
| R-TOOL-1 | Project automation **shall** be Ruby, in the Rakefile and `rakelib/`, never shell scripts; the pre-commit hook only hands over to rake. | review |
| R-CM-1 | The Rubies CI runs are those of D3; a change **shall** be its own commit, changing D3, the gemspec and the workflows together. | review |
| R-CM-2 | `Gemfile.lock` **shall** be under version control. | review |

The review checklist:

- the protocol or turborel-client cited in code (R-DOC-4) and in tests
  (R-TRACE-1);
- normal, edge and robustness tests (R-TEST-2);
- every failure a `Turborel::Error` (R-ERR-1);
- no magic numbers or strings (R-CONST);
- comments explain why (R-DOC-2);
- nothing the server sends held without bound (R-SAFE-1), and no secret
  shown (R-SAFE-4);
- CONFORMANCE.md updated (R-TRACE-3), and TODO.md where open work
  changed.

---

## 8. Platforms

| ID | Rule | Checked by |
|---|---|---|
| R-PLAT-1 | The driver **shall** run on Linux, macOS and Windows, and CI **shall** test each, on each supported Ruby (D3). | CI |
| R-PLAT-2 | Code of one platform only (Unix sockets, Windows named pipes) **shall** be chosen at run time by the platform, and **shall** refuse clearly, with a `Turborel::Error`, where its platform is not. | review; tests |
| R-PLAT-3 | Paths are joined with `File.join` and never assume a separator; files are read and written in binary or with an explicit encoding. | review |

---

## 9. Where Ruby's conventions differ

The driver follows Ruby's library conventions for layout, naming,
packaging, documentation and testing. Where they conflict with a rule
above, the rule is kept:

- Ruby libraries commonly raise `ArgumentError` or `TypeError` for a
  caller's mistake. The driver raises `Turborel::Error` for every failure
  (R-ERR-1), so a program rescues one class.
- RuboCop's default method length is 10 lines; the driver allows 50
  (R-SIZE-1), as turborel does, and keeps RuboCop's complexity limits.
- RuboCop allows disabling a cop in a comment; the driver allows it only
  in `.rubocop.yml`, with its reason (R-DEV-1).

---

## 10. References

- turborel, `doc/client/05-protocol.md`, *The Native Protocol*, version 1;
  `doc/client/02-library.md`, *The Client Library*; and
  `doc/client/02-library-connections.md`, *Settings, Pipelines and
  Pools*: the requirements.
- turborel's `client/src/` (turborel-client) and `protocol/src/`
  (turborel-protocol): the reference implementation.
- RFC 5802 and RFC 7677, SCRAM and SCRAM-SHA-256; RFC 5929 and RFC 9266,
  channel bindings for TLS; RFC 1950, the zlib format.
- [Ruby's maintenance branches](https://www.ruby-lang.org/en/downloads/branches/).
- The [RuboCop](https://docs.rubocop.org/), [Steep](https://github.com/soutaro/steep),
  [RBS](https://github.com/ruby/rbs), [minitest](https://github.com/minitest/minitest),
  [SimpleCov](https://github.com/simplecov-ruby/simplecov) and
  [YARD](https://yardoc.org/) documentation.
