# Contributing to turborel-ruby

turborel-ruby carries a program's data to and from a database people depend
on, and its passwords and keys with it. A value sent or read wrongly may
be stored wrongly for good. So a change is judged first on whether every
value arrives as it was sent, every failure is told, and no secret
leaks, and then on what it adds. The process follows the Linux kernel's,
adapted to pull requests and to a database driver.

[Before you start](#before-you-start) · [Setting up](#setting-up) ·
[Making a change](#making-a-change) ·
[Changes that touch the protocol](#changes-that-touch-the-protocol) ·
[Commit messages](#commit-messages) · [Pull requests](#pull-requests) ·
[Review](#review) · [Reporting issues](#reporting-issues) ·
[Security](#security) · [License](#license)

---

## Before you start

Read [RULES.md](RULES.md) §3 (code), §4 (tests), §6 (process) and the
decisions for your area. Every rule applies to every change, and
`bundle exec rake verify` checks those a tool can.
[CONFORMANCE.md](CONFORMANCE.md) says what is implemented of the protocol
and of turborel-client, row by row, and [TODO.md](TODO.md) lists open
work.

Open an issue first for anything larger than a fix. That covers new
features, changes to the public API, changes to a decision in RULES.md,
and new dependencies (R-DEP-1). Agreeing on the design first saves
everyone a rewrite.

The protocol starts from its spec, The Native Protocol
(`doc/client/05-protocol.md` in Turborel's repository), and from
turborel-client, the reference client (`client/src/` and
`protocol/src/`). Where they differ, the code is right. Read the section
before writing code, and cite it by its heading, as in
`[PROTOCOL Frames]` (RULES.md D6). Never cite from memory.

## Setting up

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

CI runs `bundle exec rake verify` on Linux, macOS and Windows, on each supported
runtime, and coverage on Linux (RULES.md D4, D7). A change that passes on
one platform and fails on another isn't done.

## Making a change

Keep one logical change per commit, and make each commit pass
`bundle exec rake verify` on its own, because anyone bisecting may land on it.
Move code in one commit and change it in another. Don't mix a reformat or
rename with a change of behaviour.

Tests come with the change, at the lowest level that shows it (R-TEST-1):
codec tests against the bytes the spec gives, tests of a layer over a
stream the test controls, and live tests against a server on loopback.
Cover normal cases, boundaries, and robustness cases with the exact
SQLCODE and SQLSTATE expected (R-TEST-2). Each test cites what it
verifies, by the comment above it, beginning `Verifies:` (R-TRACE-1). A fixed defect gets a test that
fails without the fix (R-TEST-6).

Documents change in the same commit. Update CONFORMANCE.md for each row
implemented (R-TRACE-4), RULES.md for a decision made or changed, and
TODO.md for open work done or found. Code never cites TODO.md.

The manual changes in the same commit too (R-DOC-7). A change to what a
program sees updates each page of [doc/](doc/README.md) that states it,
with its examples run again. The manual is laid out as Turborel's,
since turborel.com's documentation site reads it from every repository:
a chapter begins with its `# Title` and a line `[Contents](README.md)`,
links between its pages and to this repository's other files are
relative links, a link to Turborel's manual is its GitHub address,
`user/01-installing.md` keeps its name, `doc/` holds no images, and each
volume's README.md lists its chapters.

Some rules deserve a reminder.

- Every failure is the driver's error, carrying its SQLCODE and SQLSTATE
  (R-ERR-1, R-ERR-2), and no dependency is added without a decision in
  RULES.md (R-DEP-1).
- Performance claims cite measurements, with the numbers and their
  costs in memory and latency. Numbers go in the commit message, never in
  the code or the manual.
- The coverage floor only rises (R-COV-2).

## Changes that touch the protocol

These need more than passing tests. Say in the commit message what was
done for each that applies.

A codec change is tested byte by byte against the spec's layout, both
ways, at each field's bounds, the spec's worked example among them.
Bytes a server sends are read with every length and count checked
before anything is held for it (R-SAFE-1). A malformed frame fails the
connection with SQLCODE -919 and SQLSTATE 08006, never with another
failure, and is never read as something else.

A change to authentication or TLS says what an attacker in the middle
of the connection, or a server of their own, could do before and after
it, and shows that a secret is never sent where it was refused
(R-SAFE-3, R-SAFE-4). It is tested against a live server with the
mechanism concerned.

A change to what the driver asks for or sends says what a server of
another build sees. The protocol grows by capabilities, and the driver
never sends a request or a tail field of a capability it was not
granted.

A change that departs from turborel-client, in a value's mapping, an
error's SQLSTATE, a default or the reading of a setting, is refused
unless a decision in RULES.md says why.

## Commit messages

The form is Linux's.

```
area: summary in the imperative, at most 75 characters

The problem: what goes wrong, or is missing, and who it affects. A
wrong value, a crash, a hang or a secret let out is said first, with
the program that shows it.

Why this change, and how it solves the problem. Mention the choices
made and the alternatives rejected, the rules and sections applied
(RULES.md D6, R-ERR-2, [PROTOCOL Frames]), and what was measured,
with numbers.

Fixes: 54a4f0239f2e ("codec: refuse a tail tag out of order")
Closes: <link to the issue>
Reported-by: A Reporter <reporter@example.org>
```

The subject is `area: summary`, at most 75 characters, in the imperative
("refuse a frame...", not "refused"), with no full stop. It says what
changes, isn't a file name, and isn't reused within a series.

The body is wrapped at 75 columns and written for someone reading
`git log` years later with no context. Say what the change does in plain
prose, since the diff shows how. Don't write "as discussed" or "v2".

Pick the area where most of the change is. The areas down to `build` are
the same in every Turborel driver; those after them are this driver's
own.

| Area | Covers |
|---|---|
| `codec` | frames, fields, the tail, data types and values, JSON, compression |
| `transport` | TCP, Unix sockets, Windows named pipes, timeouts |
| `auth` | the mechanisms, SCRAM and its key cache |
| `tls` | TLS, its modes and channel binding |
| `session` | Hello to Ready, capabilities, status, notices, cancel, terminate, ping, reset, change-user |
| `statements` | queries, prepared statements, cursors, describe, completions |
| `lobs` | large objects by locator, and their streams |
| `copy` | copy, import and export |
| `settings` | the URI, options, environment, service and password files, several hosts and roles |
| `pipeline` | pipelines |
| `pool` | pools and the SQL-agent |
| `api` | the standard API, the public interface and the driver's error |
| `doc` | `doc/`, README.md, RULES.md, CONFORMANCE.md, TODO.md, VERSIONING.md, SECURITY.md, AGENTS.md, CLAUDE.md, this file |
| `ci` | `.github/`: workflows, issue forms, labels, Dependabot |
| `build` | the package's manifest, lock files, the checks tool and its configuration, `.githooks/`, `.gitattributes`, `.gitignore` |
| `activerecord` | the ActiveRecord adapter, `lib/active_record/` |
| `treewide` | a mechanical change across many areas |

A test goes with the code it tests, in that code's area.

Trailers go at the end, one per line, never wrapped.

| Trailer | Meaning |
|---|---|
| `Fixes: <12+ hex digits> ("<subject>")` | the commit that introduced the defect fixed |
| `Closes: <link>` | the issue this commit resolves |
| `Link: <link>` | background, such as a discussion or an issue fixed only in part |
| `Reported-by:` | who reported the defect fixed, with `Closes:` |
| `Suggested-by:` | who suggested the idea |
| `Co-authored-by:` | a co-author, as GitHub credits one |
| `Reviewed-by:` | a reviewer who checked the change and is satisfied with it |
| `Acked-by:` | a maintainer of the area who approves it without a full review |
| `Tested-by:` | someone who tested it, saying where if that matters |

`Reported-by:` and `Suggested-by:` may be added without asking. The
others name someone who said so on the record.
`git log -1 --abbrev=12 --pretty='Fixes: %h ("%s")' <commit>` writes the
`Fixes:` line.

No commit or pull request carries AI or agent attribution: no
`Co-authored-by:` of an agent, no "Generated with" line, and no
`Signed-off-by:`. Whoever submits a change answers for it.

Stage a commit by an explicit list of its paths,
`git add -- <path> ...`, never `git add -A` or `git add .` on the whole
tree, so nothing comes along unasked.

## Pull requests

A pull request is a patch series, and its description is the cover
letter. The template asks for what and why, the series commit by commit,
testing, compatibility and performance. Each commit message still stands
alone.

Base it on `main` and keep it rebased, without merging `main` into it.
When revising, rewrite the commits so the series is again what should be
merged, with no "fix review comments" commits. Force-push, and say in a
comment what changed since the last version.

Trailers given in review go into the commits they cover. Drop them from
a commit that later changes substantially, and say so.

Keep a series to about 15 commits. Split a larger one into series that
each stand alone.

## Review

Reviewers check each commit against RULES.md §6's checklist, and that
the manual is updated (R-DOC-7). For
[changes that touch the protocol](#changes-that-touch-the-protocol),
they also check that the byte-level, security and parity checks were
done. Review comments are about the change, never the person. A
reviewer who is satisfied gives `Reviewed-by:`.

## Reporting issues

Use the issue forms, **Bug**, **Conformance**, **Performance** or
**Feature**. Conformance means departing from the protocol's spec or
from turborel-client. Try the latest `main` first, and add to an
existing issue that matches rather than opening another.

Reproduce with the smallest program that shows it, with the statements,
the schema and the data it needs. A problem of the server itself, which
turborel-client shows too, goes to
[turborel](https://github.com/turborel/turborel/issues).

State the impact first. Put it in the title's first word when it is
severe.

| Tag | Meaning |
|---|---|
| `[DATA LOSS]` | data sent or stored wrongly through the driver, or lost |
| `[WRONG RESULT]` | a value or row read or sent differs from what the server holds or was given |
| `[CRASH]` | a failure that is not the driver's error, or the program brought down |
| `[HANG]` | a call that never returns, or a connection never released |
| `[REGRESSION]` | worked in an earlier commit (give the last good commit and, if you can, the first bad one) |

Give the commit (`git rev-parse --short=12 HEAD`), the runtime or
compiler and its version, the platform and architecture, the server's
version, and the connection's settings, with any password left out.

## Security

Don't open a public issue for a vulnerability. Report it privately, as
[SECURITY.md](SECURITY.md) says.

## License

turborel-ruby is under the BSD-2-Clause Plus Patent License in
[LICENSE](LICENSE), and a contribution is made under that license.
Contributors keep their copyright and own their changes. Whoever
submits a change answers for all of it, however it was written.
