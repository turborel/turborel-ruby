# turborel-ruby rules

How turborel-ruby is designed, written and verified. Every change follows
these rules; `bundle exec rake verify` checks those a tool can check, and
review checks the rest.

Rules (R-…) say how code and tests are written. **shall** is mandatory,
and a departure needs a decision recorded here (§7). **should** is
expected, and a reviewer may accept a reasoned exception.

Decisions (D1…) record how the driver is built and why. Change one only
by changing this file in a reviewed commit. A decision says what was
chosen and why, and the module it names holds the mechanism.

Cite both by ID in code, tests, reviews and commit messages, as in
`RULES.md D6` or `R-ERR-2`.

The rules are modelled on Turborel's own
[RULES.md](https://github.com/turborel/turborel/blob/main/RULES.md),
adapted to drivers. Every Turborel driver keeps the same requirement IDs
with the same meaning, and the same decisions D1 to D8, so a rule is
cited the same way in every repository; a driver's own decisions begin
at D9, and its own requirements are in families of their own. Where
Ruby's library conventions and a rule here disagree, the rule is
kept, and D8 lists where.

Before changing code, read §3 (code rules), §4 (test rules) and the
decisions covering your area. What the driver implements is in
[CONFORMANCE.md](CONFORMANCE.md), and open work is in [TODO.md](TODO.md).

[1 Decisions](#1-decisions) · [2 Layout](#2-project-layout) ·
[3 Code](#3-code-rules) · [4 Tests](#4-test-rules) ·
[5 Coverage](#5-coverage) · [6 Process](#6-process-and-tools) ·
[7 The decisions](#7-the-decisions) · [8 References](#8-references)

---

## 1. Decisions

Each is told in full in [§7](#7-the-decisions).

| # | Decision |
|---|---|
| **Shared by every Turborel driver** | |
| D1 | The native protocol, version 1, in layers that follow turborel-client |
| D2 | The language's standard API, over a low-level client of turborel-client's features |
| D3 | The runtime minimum follows the ecosystem's own support |
| D4 | One command runs every check, before each commit and in CI on three platforms |
| D5 | The version is the Turborel release's: 0.0.0 in the alpha, speaking protocol 1 |
| D6 | Tests and code cite Turborel's documents by their headings |
| D7 | A coverage floor, enforced in CI, that only rises |
| D8 | Where these rules depart from Ruby's conventions |
| **This driver's own** | |
| D9 | No runtime dependency but Ruby's own gems; bigdecimal declared |
| D10 | Development tools in the Gemfile, locked |
| D11 | Types in RBS, checked by Steep, strictly |
| D12 | RuboCop is the linter and the formatter |
| D13 | Tests are minitest |
| D14 | Coverage by SimpleCov |
| D15 | The API reference is YARD's, with nothing undocumented |
| D16 | ActiveRecord is a tool of the adapter's tests, never a dependency of the gem |

---

## 2. Project layout

| Path | What |
|---|---|
| `turborel.gemspec`, `Gemfile`, `Gemfile.lock` | the gem, and the development tools locked (D9, D10) |
| `Rakefile`, `rakelib/` | the checks tool: `verify` and each check, `coverage`, `build` (D4) |
| `rakelib/headings/` | the headings of Turborel's three documents tests cite, at a413b841 (D6) |
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
| `test/` | minitest, a `*_test.rb` for each file of `lib/`, and `test_helper.rb` (D13); `test/support/` the fake server unit tests script; `test/server/` the live tests' server set-up (R-TEST-8); `test/active_record/` the adapter's |
| `doc/` | the manual |

---

## 3. Code rules

The tools named by "the formatter", "the linters", "the type checker" and
"the checks tool" are D4's.

### R-STYLE: formatting and idiom

| ID | Rule | Checked by |
|---|---|---|
| R-STYLE-1 | Code **shall** be formatted by the formatter. | the formatter |
| R-STYLE-2 | Names **shall** follow the language's own conventions; code implementing a message, field or setting is named after it, as the spec names it. | the linters; review |
| R-STYLE-3 | Library code **shall not** print, or write to a stream it was not given. | the linters or the checks tool |
| R-STYLE-4 | What is not public **shall** be private, by the language's own means, so the public API is what is documented. | review |

### R-SIZE: short functions and files

| ID | Rule | Checked by |
|---|---|---|
| R-SIZE-1 | A function **shall** have at most 50 lines of code, blank lines and comments not counted. | the linters or the checks tool |
| R-SIZE-2 | A source file **shall** have at most 600 lines; split by the spec's sections or by layer. | the linters or the checks tool |
| R-SIZE-3 | A function **shall** take at most 5 parameters; else a structure or an options object. | the linters |
| R-SIZE-4 | A module **should** hold one concept, stated in its doc comment. | review |
| R-SIZE-5 | A function's complexity **shall** be at most 15, and its blocks nested at most 5 deep. | the linters |

### R-DOC: comments and documentation

| ID | Rule | Checked by |
|---|---|---|
| R-DOC-1 | Every public item **shall** have a doc comment in the language's documentation format, saying each parameter, what it returns, and each failure it gives. | the linters; review |
| R-DOC-2 | Comments **shall** say *why*: the section implemented, the choice made, the invariant relied on. | review |
| R-DOC-3 | The API reference, where the language's tools build one, **shall** build without warnings. | the checks tool |
| R-DOC-4 | Behaviour the protocol or turborel-client governs **shall** cite it by its heading, `[PROTOCOL Frames]`, `[CLIENT Pools]`; the driver's own choices cite their decision (D6). | review; the checks tool |
| R-DOC-5 | No commented-out code, and no `TODO`, `FIXME` or `XXX` comments: open work goes in TODO.md, and code never cites TODO.md. | the linters or the checks tool |
| R-DOC-6 | Every source file **shall** begin with a doc comment giving its responsibility and the sections it implements. | review |
| R-DOC-7 | A change a program can see **shall** update the manual, `doc/`, in the same commit; every claim is checked against the code, and every example is run. The manual keeps Turborel's layout, which turborel.com's documentation site reads: each page opens with its `# Title` and a line holding only `[Contents](README.md)`, each volume's README.md lists its pages, links within `doc/` and to other files of this repository are relative links that resolve (the site points the latter at GitHub, at the same tag), a link to Turborel's own manual is its GitHub address under `https://github.com/turborel/turborel/blob/main/doc/`, `user/01-installing.md` keeps its name, and `doc/` holds no images. | review; the checks tool |

### R-CONST: no magic numbers or strings

| ID | Rule | Checked by |
|---|---|---|
| R-CONST-1 | Numbers in library code other than `0` or `1` **shall** be named constants, documenting the value's source. | the linters; review |
| R-CONST-2 | Every protocol tag **shall** be a named constant, defined once: a message's kind, a data type's and a value's tag, a tail tag, a capability's name, a mechanism's name, a status name, and each SQLSTATE the driver raises. | review |
| R-CONST-3 | Strings matched or looked up, such as settings' names, URI parts and environment variables, **shall** be named constants. Messages for people are not. | review |
| R-CONST-4 | Related constants **shall** live together in their layer's module, under a comment naming the section they come from. | review |
| R-CONST-5 | Tests may use literal fixtures, as the spec prints its bytes; an expected value restating a constant **should** use it. | review |

### R-ERR: errors

| ID | Rule | Checked by |
|---|---|---|
| R-ERR-1 | Every failure the library gives **shall** be the driver's error (D2): no stray exception, panic, abort, assertion or other error of the language or its libraries reaches a program, and no library code ends the process. | the linters; tests; review |
| R-ERR-2 | Each failure **shall** carry its SQLCODE, SQLSTATE and message, and, once read from a server, the rest of it: the rule it cites, its position, whether a transaction is still active, and its diagnostics. A failure the driver raises itself carries the SQLCODE and SQLSTATE turborel-client gives the same failure. | tests |
| R-ERR-3 | No failure **shall** be silenced. One caught and given again as the driver's keeps its cause; a result left unread says why it cannot matter. | the linters; review |
| R-ERR-4 | A connection that fails **shall** be closed, and every request waiting on it given that failure; a failed call leaks nothing and leaves nothing waiting. | tests; review |

### R-NUM: integers and numbers

| ID | Rule | Checked by |
|---|---|---|
| R-NUM-1 | Every integer of the protocol **shall** be read and written at its width, little-endian, explicitly: never by the platform's byte order, by casting a buffer, or by bitwise operators on numbers wider than the language's operators keep exact. | review; tests |
| R-NUM-2 | A value out of range for its field, or for the type it is read into, **shall** be refused with the driver's error, never truncated, wrapped or rounded. | tests |
| R-NUM-3 | An exact number (units `i128`, scale `u32`) and a DECFLOAT **shall** never pass through a binary floating-point type. | review; tests |
| R-NUM-4 | An approximate number **shall** keep its bits: NaN and -0.0 are read and written as the double they are, and floats are compared bit for bit, never for equality. | tests; review |
| R-NUM-5 | In a language whose integers are bounded, arithmetic on sizes, counts and offsets **shall** be shown not to overflow before it is done. | the linters; review |

### R-LINT: warnings

| ID | Rule | Checked by |
|---|---|---|
| R-LINT-1 | A warning is an error: of the compiler, the linters and the type checker, and of the runtime itself while the tests run. | the checks tool |
| R-LINT-2 | The strictest standard linters and type checking the language has **shall** be on; a check left off says why in the configuration that leaves it off. | review |
| R-LINT-3 | A warning **shall** be silenced only on its line, naming its rule and saying why; a suppression no longer needed **shall** be removed. | the linters; review |

### R-DEP: dependencies

| ID | Rule | Checked by |
|---|---|---|
| R-DEP-1 | The library **shall** depend on nothing but the language's standard library and runtime, unless a decision here admits a dependency, with its reason, version, license and review. | review |
| R-DEP-2 | A dependency, of the library or of its tools, **shall** be production-grade by its makers' own claims: a stable release they support. | review |
| R-DEP-3 | Tools **shall** be pinned by version, with the ecosystem's lock file under version control where it has one; a change of a tool's version is a commit of its own. | review |

### R-SAFE: what a server sends, and secrets

| ID | Rule | Checked by |
|---|---|---|
| R-SAFE-1 | A length or count a server, or a file the driver reads, gives **shall** be checked against what follows and the limit taken before anything is held for it, so no reply takes the program's memory without bound. | tests; review |
| R-SAFE-2 | What a server sends **shall** never be run, loaded or deserialized as code. | the linters; review |
| R-SAFE-3 | TLS **shall** be used and verified as the settings ask, and a connection **shall not** fall back to less than its mode allows. | tests |
| R-SAFE-4 | A secret (a password, anything derived from one, a SCRAM key or proof, a cancel key) **shall** never be logged, put in a failure's message or an object's display form, or sent where it was refused; where the language allows, it is cleared from memory once used. | tests; review |
| R-SAFE-5 | No module-level mutable state: what lasts belongs to an object a program made, such as a connection, a pool or a key cache. | review |
| R-SAFE-6 | The library **shall** start no thread, timer or task but for an object a program made, and a closed connection, cursor or pool leaves none behind. | tests; review |

### R-PLAT: platforms

| ID | Rule | Checked by |
|---|---|---|
| R-PLAT-1 | The driver **shall** run on Linux, macOS and Windows, on every runtime D3 supports; CI checks each (D4). | CI |
| R-PLAT-2 | Code of one platform, such as a Unix socket or a named pipe, **shall** be chosen by the platform, and elsewhere refused with the driver's error, saying so; never silently something else. | tests; review |
| R-PLAT-3 | Paths **shall** be made by the language's path functions, and files kept with LF line endings (`.gitattributes`). | review |
| R-PLAT-4 | Code built for one platform only **shall** say, when handed back, that it was not run on the others. | review |

### R-TYPE: types

| ID | Rule | Checked by |
|---|---|---|
| R-TYPE-1 | Every class, module, method and constant of `lib/`, but the ActiveRecord adapter's, written to ActiveRecord's interfaces, which have no signatures (D16), **shall** have its signature in `sig/`, in RBS, and Steep **shall** pass with its strict diagnostics. | Steep |
| R-TYPE-2 | A Steep annotation that casts a value (`_ = ...`) **shall** say in a comment why the value has the type it is given. | review |
| R-TYPE-3 | The signatures **shall** pass `rbs validate`. | rbs |

---

## 4. Test rules

### R-TEST: levels and layout

| ID | Rule | Checked by |
|---|---|---|
| R-TEST-1 | A test **shall** sit at the lowest level that shows its requirement: a codec test of bytes, a test of a layer over a stream the test controls, a test of the API, or a live test against a server. | review |
| R-TEST-2 | Tests **shall** derive from the spec and turborel-client, not from the code: normal cases, boundaries included, and robustness cases with the exact SQLCODE and SQLSTATE expected. | review |
| R-TEST-3 | A test's name **shall** say the behaviour checked. | review |
| R-TEST-4 | Test code may assert, print and use literal fixtures; every other rule applies. | the linters' configuration |
| R-TEST-5 | Tests **shall** be deterministic and independent: no clock, randomness, network beyond loopback, or order between them. A case generator uses a fixed seed. A live test runs against a server on loopback that its own set-up starts, on its own port and data directory. | review |
| R-TEST-6 | Every fixed defect **shall** get a regression test that fails without the fix, its doc comment saying so. | review |
| R-TEST-7 | A fixture or helper shared by tests **shall** be written once, in one place. Tests use the one framework D9 or later names, no other. | review |
| R-TEST-8 | Live tests **shall** run against `ghcr.io/turborel/turborel:nightly` in CI, set up by the repository's own server set-up, with test certificates, SCRAM users and SERVER.TRUST_LOCAL. | CI |
| R-TEST-9 | SCRAM **shall** be tested by RFC 7677's test vector, and settings by the URI, service file, password file and environment cases of turborel-client's settings tests, so every driver reads settings as turborel-client does. | review |

### R-TRACE: traceability

| ID | Rule | Checked by |
|---|---|---|
| R-TRACE-1 | Every test **shall** cite what it verifies, by the comment above it, beginning `Verifies:`, beginning with a tag of D6: `[PROTOCOL <heading>]`, `[CLIENT <heading>]`, `[DESIGN] D<n>` or `[TOOL] R-<id>`. | the checks tool |
| R-TRACE-2 | A citation **shall** name a heading, decision or rule that exists. | the checks tool |
| R-TRACE-3 | Code implementing a requirement **shall** cite it (R-DOC-4). | review |
| R-TRACE-4 | CONFORMANCE.md **shall** change with the change that implements or changes a row. A row is marked done only where the driver's code for it exists and tests citing its section pass, or, of a driver built over another, as CONFORMANCE.md says. | review |

---

## 5. Coverage

| ID | Rule | Checked by |
|---|---|---|
| R-COV-1 | Coverage **shall** be measured by `bundle exec rake coverage`, over the library and every test. | the checks tool |
| R-COV-2 | Coverage **shall not** fall below the floor (D7); a change raising it **should** raise the floor. | the checks tool, in CI |
| R-COV-3 | A gap is closed by a test derived from a requirement, or by removing dead code; never by a test of no requirement, and never by excluding the code. | review |

---

## 6. Process and tools

| ID | Rule | Checked by |
|---|---|---|
| R-PROC-1 | `bundle exec rake verify` **shall** pass before every commit; CI adds every platform, every supported runtime and the coverage floor (D4). | pre-commit hook; CI |
| R-PROC-2 | Every change **shall** be reviewed against the checklist below. | review |
| R-PROC-3 | Commits **should** be small and single-purpose, in CONTRIBUTING.md's form (`area: summary`, then why), citing the rules applied or changed. | review |
| R-PROC-4 | A threshold change **shall** change RULES.md and the configuration that holds it together. | review |
| R-PROC-5 | Project automation **shall** be written in the language's own tooling, never shell scripts; the git hook only hands over to the checks tool. | review |
| R-PROC-6 | CI's actions **shall** be pinned by their full commit SHA, with the version in a comment. | review |
| R-PROC-7 | A release **shall** be published only as VERSIONING.md says, by the owner (D5). | review |

The review checklist:

- the spec or turborel-client cited in code (R-DOC-4) and tests
  (R-TRACE-1);
- normal and robustness tests (R-TEST-2), and a failing-first test for a
  fix (R-TEST-6);
- every failure the driver's, carrying its condition (R-ERR);
- no magic numbers or strings, protocol tags named (R-CONST);
- every length a server sends bounded, no secret disclosed (R-SAFE);
- comments explain why (R-DOC-2);
- CONFORMANCE.md (R-TRACE-4), the manual (R-DOC-7) and TODO.md updated
  where they change.

---

## 7. The decisions

### Shared by every Turborel driver

#### D1. The native protocol, version 1, in layers that follow turborel-client

The driver speaks Turborel's native protocol, version 1, as
`doc/client/05-protocol.md` in Turborel's repository lays it out,
itself, in Ruby alone, with no native extension. Where that page and turborel-protocol's code differ,
the code is right, and the driver follows it; CONFORMANCE.md names each
such place.

The reference is turborel-client. The driver does all it does before it
is called done, row by row in CONFORMANCE.md, and is built in the same
layers as turborel-client's modules, so a reviewer checks one against
the other. Each layer is a commit area of CONTRIBUTING.md.

| Layer | What it covers | turborel-client |
|---|---|---|
| `codec` | the 5-byte frame header; fields; the tail and its tag order; the data types and values; JSON values; zlib `z` frames within the length bound; the 16 MiB body limit | `protocol/src` |
| `transport` | TCP on 7422; Unix sockets; the Windows named pipe `\\.\pipe\turborel`; TLS begun on the same port; the connect and read timeouts | `target.rs`, `timeouts.rs`, `pipe.rs` |
| `auth`, `tls` | trust, password, certificate, SCRAM-SHA-256 and -PLUS; secrets refused over plain TCP; the SCRAM key cache; TLS | `mechanism.rs`, `scram.rs`, `tls.rs` |
| `session` | Hello, Ready, Status, notices, conditions, diagnostics, autocommit, cancel, terminate, ping, reset, change-user, query attributes, multi-statement | `connection.rs`, `session.rs`, `cancel.rs`, `told.rs` |
| `statements` | queries and streamed queries; prepare, execute, fetch, close, deallocate; numbered cursors; describe; completions | `statements.rs`, `frames.rs` |
| `lobs`, `copy` | locators, their reads, writes and streams; copy, import and export | `lobs.rs`; `copy.rs`, `import/`, `export.rs` |
| `settings` | the URI, options, variables, service and password files, several hosts, roles, TLS modes, channel binding | `settings/`, `failover.rs`, `role.rs` |
| `pipeline`, `pool` | pipelines; pools; the SQL-agent | `pipeline.rs`; `pool/`, `agent.rs` |
| `api` | the standard API (D2) | the language's own |

Each layer is a directory of `lib/turborel/`, the codec's
`lib/turborel/protocol/`, its classes and modules marked `@api private`.
Ruby gives what the layers need: `openssl` for TLS, SHA-256, HMAC and
PBKDF2, `zlib` for compressed frames, and `socket` for TCP and Unix
sockets, each shipped with Ruby (D9).

#### D2. The language's standard API, over a low-level client of turborel-client's features

The driver's standard interface is a plain API in the manner of the pg gem, and an ActiveRecord adapter for Rails 8.1 and later, so a program, and the
tools built for Ruby's database interface, use it as they use
any other driver. It sits over a low-level client that has every feature
of turborel-client. What the standard interface has no place for, such
as pipelines, pools, copy, large objects by locator, notices and the
session's status, is reached through the low-level client or the
driver's own extensions of the standard interface.

Every failure is the driver's error, carrying its SQLCODE and SQLSTATE
(R-ERR). The standard interface is built at milestone M7 and checked in
M8's audit; until then its names may change.

Ruby has no standard database interface of its own; what Ruby programs
know is the pg gem's: a connection, `exec` and `exec_params`, `prepare`
and `exec_prepared`, results read by row and by column, and
transactions. So the plain API, under `require "turborel"`, takes that
shape: `Turborel.connect`, `Turborel::Connection` and `Turborel::Result`.
It is a shape, not a copy: names and behaviour follow Turborel, not
PostgreSQL, where they differ.

Rails is how most Ruby programs reach a database, so the gem also
carries an ActiveRecord adapter for Rails 8.1 and later, under its own
require path, `active_record/connection_adapters/turborel_adapter`,
registered as the adapter `turborel`. ActiveRecord is not a dependency
of the gem: a program that uses the adapter has Rails already, and one
that does not never loads it.

The driver's error is `Turborel::Error`, carrying SQLCODE, SQLSTATE and
message. An exact number of scale 0 is read as an Integer, one of a
greater scale as a BigDecimal, exactly.

#### D3. The runtime minimum follows the ecosystem's own support

The driver supports Ruby 3.3 or later. The rule is the ecosystem's own:
support every release its makers still support, and drop each at its
end of life. Where a major framework of the language sets a higher
floor, the driver matches it. The minimum changes in a commit of its
own, which changes this decision, the package's metadata, CI and
README.md together.

In November 2026 Ruby's core team maintains 3.3 (in security
maintenance, its end of life expected on 2027-03-31), 3.4 and 4.0; 3.2
reached its end of life on 2026-04-01. Rails 8.1, which the adapter
targets, needs Ruby 3.2, so it sets no higher floor. The gemspec's
`required_ruby_version` is `>= 3.3`, and CI tests 3.3, 3.4 and 4.0.

#### D4. One command runs every check, before each commit and in CI on three platforms

`bundle exec rake verify` runs every check a change must pass, stopping at the
first failure: the formatter, the linters, the type checker where the
language has one, the checks tool's own rules (lengths a linter does not
measure, citations and their targets, open-work markers, the manual's
titles, `[Contents](README.md)` lines and links), and every test.
`bundle exec rake coverage` measures coverage and holds it to its floor (D7).

`.githooks/pre-commit` hands over to the same command. It is a script
only because git runs hooks as scripts. CI runs it on Linux, macOS and
Windows, over every runtime D3 supports, with the live tests against the
nightly image and coverage on Linux. Every action is pinned by its full
commit SHA, its version in a comment, and Dependabot proposes each bump.

`bundle exec rake verify` runs, in order: RuboCop, as linter and
formatter (D12); `rake rules`, the checks tool's own rules, in
`rakelib/rules.rake`; Steep and `rbs validate` (D11); YARD (D15); and
the tests, with Ruby's warnings about `lib/` failing them (D13). CI runs
each as a step of its own, so a failure names its check, and
`bundle exec rake install_hooks` points git at `.githooks/`.

#### D5. The version is the Turborel release's: 0.0.0 in the alpha, speaking protocol 1

The driver has no version scheme of its own. Its version is the number
of the Turborel release it is made for, the same as the server's: a
Turborel release and each driver's release for it share the number,
**MAJOR.MINOR.PATCH**, as Turborel's VERSIONING.md numbers it. The alpha
is 0.0.0, as Turborel's is, and speaks protocol version 1.

The number is written once, in `Turborel::VERSION`, in `lib/turborel/version.rb`. Nothing is
published, and no release is tagged, until every Turborel driver is
done; then the owner publishes them together (VERSIONING.md).

#### D6. Tests and code cite Turborel's documents by their headings

A test cites what it verifies, and code what it implements, by the
heading of the section that says it, as printed:

- `[PROTOCOL <heading>]`, a heading of The Native Protocol,
  `doc/client/05-protocol.md`, as `[PROTOCOL Frames]`;
- `[CLIENT <heading>]`, a heading of The Client Library,
  `doc/client/02-library.md`, or of Settings, Pipelines and Pools,
  `doc/client/02-library-connections.md`, which share no heading, as
  `[CLIENT Pipelines]`;
- `[DESIGN] D<n>`, a decision of this file;
- `[TOOL] R-<id>`, a rule the checks tool holds, for the tool's own
  tests.

What else a test relies on follows the tag, as an RFC by its section:
`[PROTOCOL Mechanisms] [RFC 7677 §3]`. The heading `Lob 'L'` is printed
twice in The Native Protocol, under Requests and under Replies, so a
citation of it says which it means.

The checks tool keeps the headings of those three documents, copied at
the Turborel commit CONFORMANCE.md names, and refuses a citation of a
heading, decision or rule that is not there (R-TRACE-2). In Ruby,
a test cites by the comment above it, beginning `Verifies:`.

#### D7. A coverage floor, enforced in CI, that only rises

`bundle exec rake coverage` measures the library's coverage over every test,
and CI fails below the floor. In every Turborel driver the floor is at
least 90 % of lines, and of branches where the tool measures them. It
only rises: a change that raises coverage well above it raises it. A
floor below 100 % says why.

The floor is 99 % of lines and 96 % of branches of `lib/`, kept in
`.simplecov` (D14). It is below 100 % because code of one platform,
Unix sockets and Windows named pipes, runs only where its platform
does, and coverage is measured on Linux.

#### D8. Where these rules depart from Ruby's conventions

The driver follows its language's library conventions for layout,
naming, packaging, documentation and testing. Where one conflicts with a
rule here, the rule is kept:

- Libraries commonly leave the length of functions and files to taste.
  These are bounded (R-SIZE).
- Libraries commonly fail an argument out of range with the language's
  own error. Here every failure is the driver's, an argument's too, with
  the SQLCODE and SQLSTATE turborel-client gives it (R-ERR-1), so a
  program handles one kind of failure.

- RuboCop lets a cop be disabled by a comment on its line. Here no cop
  is disabled in source: a deviation is kept in `.rubocop.yml`, with
  its rule and its reason, where review sees every one (R-LINT-3).
- RuboCop's default method length is 10 lines; R-SIZE-1's 50 is used,
  while RuboCop's complexity limits, stricter than R-SIZE-5's, are
  kept.
- Where turborel-client has no case of its own, as for a Ruby value of
  a class the protocol does not carry, the driver gives the codes every
  Turborel driver gives: SQLSTATE 22000, SQLCODE -301, for a value the
  protocol cannot carry; 0A000, -900, for what is past Turborel's
  limits; TB910, -910, for a misuse it has no case for, as an argument
  none of those a method takes. The plain API's `exec_prepared` or
  `deallocate` of a name no statement is prepared under gives SQLCODE
  -921, SQLSTATE 26000, as Turborel's own EXECUTE does
  ([Appendix B](doc/appendix/b-errors.md)).
- Where turborel-client reads a reply's value with the decoder of a
  stored one, it fails a malformed value as a stored one: a truth value
  or a string's units byte other than 0 or 1, a JSON value damaged, or a
  condition of a Complete that cannot be read, with SQLCODE -916, and a
  JSON value nested past 128 with -900, the connection kept, though the
  replies after it then come out of turn. The page fails a connection on
  a malformed message ([PROTOCOL Frames], [PROTOCOL Errors and
  notices]), and the driver follows it: each is SQLCODE -919, SQLSTATE
  08006, the connection lost. So too a value of a tag the page's table
  does not list, as 5, 7, 10, 12, 18 and 19, which turborel-client reads
  by its type's decoder and the server never sends.
- During a copy the driver refuses, before sending it, every request
  but CopyData, CopyEnd and Ping, Terminate among them (TB910), where
  turborel-client's copy borrows the connection and so sends none.

### This driver's own

#### D9. No runtime dependency but Ruby's own gems; bigdecimal declared

The driver needs TLS, SHA-256 and HMAC, PBKDF2, zlib, sockets and a type
that holds every exact number the protocol carries (an `i128` of units
and a `u32` scale). Ruby has each: `openssl`, `zlib` and `socket`, which
ship with Ruby as default gems or its own extensions, and `bigdecimal`.
No other gem is a runtime dependency, so nothing outside Ruby's own
releases needs to be trusted.

`bigdecimal` was a default gem up to Ruby 3.3, and is a bundled gem from
3.4 (3.4 ships 3.1.8, 4.0 ships 4.0.1). A bundled gem is installed with
Ruby but, under Bundler, can be required only if it is declared. So the
gemspec declares `bigdecimal`, `>= 3.1` (Ruby 3.3's default is 3.1.5),
`< 5`. It is still Ruby's own gem, maintained by Ruby's core team.

#### D10. Development tools in the Gemfile, locked

The tools a contributor needs are in the Gemfile's `development` group,
not in the gemspec, as Bundler's own gem template has them: rake,
minitest, RuboCop with its minitest, performance and rake plug-ins, rbs,
Steep, SimpleCov and YARD, and ActiveRecord for the adapter's tests
(D16). Each is the Ruby community's standard tool
for its job, maintained as production software. `Gemfile.lock` is
committed (R-DEP-3), with every platform CI runs on, so each run
installs the same versions, and Dependabot proposes updates to it. Gems
are installed into the clone, by
`bundle config set --local path vendor/bundle`, never system-wide.

#### D11. Types in RBS, checked by Steep, strictly

Every file of `lib/` has its signatures in `sig/`, in RBS, Ruby's own
type language, but the ActiveRecord adapter's and its registration's
(D16). Steep checks `lib/` against them with its strict
diagnostics (`Steepfile`), and `rbs validate` checks the signatures
themselves. Steep, not rbs alone, because rbs checks only that the
signatures are well formed, and Steep checks the code against them
(R-TYPE).

#### D12. RuboCop is the linter and the formatter

Ruby has no formatter apart from its linter in common use, so RuboCop's
layout cops are the formatter, and `rubocop -a` applies them. Its
configuration (`.rubocop.yml`) enables every new cop as it comes, and
some off by default: method documentation, explicit error classes,
number conversion, require order, and no cop disabled in source. Every
offense fails `verify`.

#### D13. Tests are minitest

Tests are minitest, the test framework that ships with Ruby, under
`test/`, a `*_test.rb` file for each file of `lib/`, each requiring
`test_helper.rb`, run by `rake test`. Minitest runs a file's tests in an
order drawn from a seed it prints: the order changes, the tests do not,
so a test that depends on another fails and the seed repeats it
(R-TEST-5). A Ruby warning about `lib/` fails the test that set it off
(R-LINT-1).

#### D14. Coverage by SimpleCov

`rake coverage` runs the tests under SimpleCov, measuring the lines and
branches of `lib/`, and fails below the floor `.simplecov` keeps (D7).

#### D15. The API reference is YARD's, with nothing undocumented

Doc comments are YARD's, the format RubyGems' documentation sites read.
`rake doc` builds the reference into `api/`, failing on any warning
or on any class, module, method or constant with no documentation
(R-DOC-1, R-DOC-3). Classes and modules internal to the driver are
marked `@api private` and left out of the reference (R-STYLE-4).

#### D16. ActiveRecord is a tool of the adapter's tests, never a dependency of the gem

The ActiveRecord adapter (D2) cannot be tested without ActiveRecord, so
`activerecord`, 8.1 or later, is in the Gemfile's `development` group,
locked as D10's tools are (R-DEP-3), with what it needs. It is never in
the gemspec, so the gem depends on it at no time (R-DEP-1, D9): a
program that uses the adapter has Rails, and ActiveRecord, already, and
one that does not never loads it. ActiveRecord is the Rails project's,
maintained as production software under the MIT License (R-DEP-2). The
adapter is written to ActiveRecord's interfaces, which have no RBS of
their own, so Steep passes over it (D11), and its tests, against a live
server, check it.

---

## 8. References

- Turborel, `doc/client/05-protocol.md`, *The Native Protocol*,
  version 1: the requirements of the codec and every message.
- Turborel, `doc/client/02-library.md`, *The Client Library*, and
  `doc/client/02-library-connections.md`, *Settings, Pipelines and
  Pools*, and the crates turborel-client and turborel-protocol: the
  features to match, and the reference where the spec is silent or
  differs.
- Turborel, `RULES.md` D89, the JSON value's binary tree, and D184, the
  UUID's tag.
- RFC 1950, *ZLIB Compressed Data Format Specification*; RFC 5802 and
  RFC 7677, SCRAM and SCRAM-SHA-256; RFC 5929 and RFC 9266, the
  `tls-server-end-point` and `tls-exporter` channel bindings.
- The standards of Ruby and of its database interface, named in
  D2 and D3.
