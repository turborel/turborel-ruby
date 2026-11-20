# Guide for coding agents

How to work on turborel-ruby as a coding agent, with any tool. If this file
disagrees with [RULES.md](RULES.md) or [CONTRIBUTING.md](CONTRIBUTING.md),
follow those.

turborel-ruby is the Ruby driver for turborel, a relational database
system. It speaks turborel's native protocol, version 1, in Ruby alone,
and is built to match turborel-client, turborel's own client library,
feature for feature, with a plain API in the manner of the pg gem and an
ActiveRecord adapter over it. See [README.md](README.md).

## Before you change anything

Read RULES.md §3 (code), §4 (tests), §7 (process) and the §1 decisions for
your area. Read CONTRIBUTING.md for how a change is made and the extra
checks for changes to the protocol's handling.

## Build and check

Ruby 3.3 or later. Gems go into the clone, never system-wide. Every change
must pass `bundle exec rake verify` and `bundle exec rake coverage` before
it is handed back.

```
bundle config set --local path vendor/bundle   # once per clone
bundle install
bundle exec rake verify          # every check a change must pass
bundle exec rake coverage        # the tests under SimpleCov, and its floors
bundle exec rake install_hooks   # run verify before every commit (once per clone)
bundle exec rake rubocop         # lint and format; `bundle exec rubocop -a` fixes the format
bundle exec rake rules           # file length, printing and exits, open-work markers, links, test citations
bundle exec rake steep           # types: lib/ against sig/
bundle exec rake rbs             # the signatures themselves
bundle exec rake doc             # the API reference, failing on anything undocumented
bundle exec rake test            # the tests alone
bundle exec rake build           # the gem, in pkg/
TURBOREL_DOC=<turborel>/doc/client bundle exec rake rules
                                 # and every [PROTOCOL ...] and [CLIENT ...] heading cited
```

`verify` stops at the first failure. CI runs it on Linux, macOS and
Windows, on Ruby 3.3, 3.4 and 4.0, and coverage on Linux (D7). Coverage
floors are in `.simplecov` and only rise (R-COV-2).

Project automation is Ruby, in the Rakefile and `rakelib/`, never shell
scripts (R-TOOL-1).

## Where things are

| Path | What |
|---|---|
| `lib/turborel.rb` | the gem's root module |
| `lib/turborel/version.rb` | `Turborel::VERSION`, the turborel release it is made for (D12) |
| `lib/turborel/error.rb` | `Turborel::Error`, every failure (R-ERR-1) |
| `lib/turborel/protocol/` | the codec, no I/O: so far the frame header (D1) |
| `sig/` | RBS signatures, one file for each file of `lib/` (D6) |
| `test/` | minitest, one `*_test.rb` for each file of `lib/` (D9) |
| `rakelib/` | the `rules` and `doc` tasks |
| `doc/` | the manual: `user/` the User's Guide, `client/` the API Reference, `appendix/` the appendices |

The spec and the reference are in turborel's repository:
`doc/client/05-protocol.md` (the protocol), `doc/client/02-library.md` and
`02-library-connections.md` (turborel-client's features), `client/src/`
and `protocol/src/` (their code). Where the page and the code differ, the
code is right.

## Rules that are broken most often

`verify` treats every RuboCop offense as an error. RULES.md §3 and §4 have
the full list.

- Every failure is a `Turborel::Error` with SQLCODE and SQLSTATE; never
  `ArgumentError`, `RuntimeError` or a bare `raise "..."`. An exception
  from Ruby or the system is rescued where it arises and raised as one
  (R-ERR-1, R-ERR-2).
- No `puts`, `print`, `p`, `warn`, `exit` or `abort` in `lib/` (R-STYLE-5,
  R-ERR-3).
- Keep methods to 50 lines and 5 parameters, keywords counted, and files to
  600 lines (R-SIZE).
- No magic numbers or strings; every protocol tag, kind and capability
  name is a named constant (R-CONST).
- Every class, module, method and constant has a YARD comment (R-DOC-1).
- Every method in `lib/` has its signature in `sig/`, and Steep passes
  strictly (D6). A cast, `_ = ...`, says why in a comment (R-DEV-2).
- Comments say why (R-DOC-2). No `TODO` comments or commented-out code
  (R-DOC-5).
- No `# rubocop:disable`; a deviation goes in `.rubocop.yml` with its
  reason (R-DEV-1).
- No runtime dependency without a decision in RULES.md (R-SAFE-2).
- Check every length and count the server sends before using it
  (R-SAFE-1), and never show a secret (R-SAFE-4).
- Code of one platform is chosen at run time and refuses clearly
  elsewhere (R-PLAT-2).

## Tests

Every test's comment begins `# Verifies:` and a tag `rake rules` accepts
(R-TRACE-1): `[PROTOCOL <heading>]` for `05-protocol.md`,
`[CLIENT <heading>]` for `02-library.md` or `02-library-connections.md`,
`[RFC <number> ...]`, or `[DESIGN]` and the decision.

Tests are deterministic, with no clock, randomness or network beyond
loopback (R-TEST-3). Shared helpers go in `test/test_helper.rb` (R-TEST-6).
A fixed defect gets a regression test (R-TEST-5).

## Citing the spec

Check every citation against the page before writing it: a heading cited
must be a heading of the page. Never cite from memory. Run `rake rules`
with `TURBOREL_DOC` pointing at turborel's `doc/client/` to check them.

Code never cites TODO.md, and `rake rules` refuses it (R-DOC-5).

## Documents

A finished feature updates these in the same change:

- RULES.md, if it made a decision, including the row in §1's table
- CONFORMANCE.md, for each row implemented or changed (R-TRACE-3)
- TODO.md, which only holds open work
- [doc/](doc/README.md), for anything a program sees (R-DOC-6): the
  chapter of the User's Guide, the page of the API Reference and the
  appendix that state it. turborel.com's docs site reads `doc/`, so keep
  its layout: each chapter's `# Title`, then `[Contents](README.md)`, and
  relative `.md` links only
- README.md, if what it says the driver does changes

Every claim in a document is checked against the code, and every example
is run.

## Commits

- Commit only when the maintainer asks, and never push without approval.
- Follow CONTRIBUTING.md's form, with one logical change per commit.
- Add no AI or agent attribution to a commit or pull request. That means
  no `Co-Authored-By` for an agent, no "Generated with" and no
  `Signed-off-by`.
- Stage with an explicit path list, `git add -- <path> ...`. Never use
  `git add -A` or `git add .` on the whole tree.
- Never stage `LICENSE` or scratch files.
- Code for one platform only can't be verified locally on another. Say so
  when handing it back.
