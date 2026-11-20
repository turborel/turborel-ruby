# Contributing to turborel-ruby

turborel-ruby carries a program's data, its passwords and its statements
to a turborel server and back. A driver that reads a reply wrongly gives
a wrong result, and one that leaks a secret or skips TLS exposes what it
carries. So a change is judged first on whether it keeps the protocol
right and the connection safe, and then on what it adds. The process
follows the Linux kernel's, adapted to pull requests, as turborel's own
does.

[Before you start](#before-you-start) · [Setting up](#setting-up) ·
[Making a change](#making-a-change) ·
[Changes to the protocol's handling](#changes-to-the-protocols-handling) ·
[Commit messages](#commit-messages) · [Pull requests](#pull-requests) ·
[Review](#review) · [Reporting issues](#reporting-issues) ·
[Security](#security) · [License](#license)

---

## Before you start

Read [RULES.md](RULES.md) §3 (code), §4 (tests), §7 (process) and the
decisions for your area. Every rule applies to every change, and
`bundle exec rake verify` checks those a tool can.
[CONFORMANCE.md](CONFORMANCE.md) says what is implemented of the protocol
and of turborel-client, and [TODO.md](TODO.md) lists open work.

Open an issue first for anything larger than a fix. That covers new
features, changes to a decision in RULES.md, new dependencies (R-SAFE-2)
and changes to the API. Agreeing on the design first saves everyone a
rewrite.

The protocol starts from its page, `doc/client/05-protocol.md` in
turborel's repository, and turborel-client's code (`client/src/` and
`protocol/src/`). Where they differ, the code is right. Read the section
before writing code, and cite it by its heading, as in
`[PROTOCOL Frames]` or `[CLIENT Pipelines]` (R-DOC-4). Never cite from
memory.

## Setting up

Ruby 3.3 or later, and Bundler, which ships with it.

```
bundle config set --local path vendor/bundle   # gems in the clone, never system-wide
bundle install
bundle exec rake install_hooks                 # run verify before each commit (once per clone)
bundle exec rake verify                        # every check a change must pass
bundle exec rake coverage                      # the tests, and the coverage floors, as CI runs them
```

The checks one at a time:

```
bundle exec rake rubocop     # lint and format (rubocop -a applies the format)
bundle exec rake rules       # file length, printing, open-work markers, links, citations
bundle exec rake steep       # types, lib/ against sig/
bundle exec rake rbs         # the signatures themselves
bundle exec rake doc         # the API reference, nothing undocumented
bundle exec rake test        # the tests
TURBOREL_DOC=../turborel/doc/client bundle exec rake rules
                             # and each [PROTOCOL ...] and [CLIENT ...] heading cited
```

CI runs `verify` on Linux, macOS and Windows, on Ruby 3.3, 3.4 and 4.0,
and coverage on Linux (RULES.md D7). A change that passes on one platform
and fails on another isn't done.

## Making a change

Keep one logical change per commit, and make each commit pass
`bundle exec rake verify` on its own, because anyone bisecting may land on
it. Move code in one commit and change it in another. Don't mix a
reformat or rename with a change of behaviour.

Tests come with the change. Cover normal cases, edges, and robustness
cases with the exact SQLCODE and SQLSTATE expected (R-TEST-2). Each test's
comment starts with `# Verifies:` and what it verifies (R-TRACE-1). A
fixed defect gets a test that fails without the fix (R-TEST-5).

Documents change in the same commit. Update CONFORMANCE.md for a row
implemented or changed (R-TRACE-3), RULES.md for a decision made or
changed, and TODO.md for open work done or found. Code never cites
TODO.md.

The manual changes in the same commit too (R-DOC-6). A change to what
programs see updates each page of `doc/` that states it, with its
examples run again. The manual is laid out as turborel's, since
turborel.com's docs site reads it from here: [doc/README.md](doc/README.md)
the set, `doc/user/` the User's Guide, `doc/client/` the API Reference,
`doc/appendix/` the appendices. Each chapter begins with its `# Title`,
then a line `[Contents](README.md)`, and links between pages are relative
`.md` links.

Some rules deserve a reminder.

- Every failure is a `Turborel::Error` (R-ERR-1), and no dependency comes
  without a decision in RULES.md (R-SAFE-2).
- Nothing the server sends is held without bound (R-SAFE-1), and no secret
  is shown (R-SAFE-4).
- Coverage floors only rise (R-COV-2).

## Changes to the protocol's handling

These need more than passing tests. Say in the commit message what was
done for each that applies.

A codec change is tested byte by byte, from the protocol's page, with the
malformed forms that must fail the connection (SQLCODE -919, SQLSTATE
08006).

A change to TLS, authentication or channel binding says which settings
it affects, and shows by a test that a connection that asked for TLS, a
verified certificate or a binding never goes on without it.

A change to what the driver asks for in Hello, or does with a capability,
says what an older or a newer server sees.

## Commit messages

The form is Linux's.

```
area: summary in the imperative, at most 75 characters

The problem: what goes wrong, or is missing, and who it affects. A
wrong result, a lost connection or a leaked secret is said first, with
the steps that show it.

Why this change, and how it solves the problem. Mention the choices
made and the alternatives rejected, and the rules and sections applied
(RULES.md D4, R-ERR-1, [PROTOCOL Frames]).

Fixes: 54a4f0239f2e ("codec: refuse a tail tag out of order")
Closes: <link to the issue>
Reported-by: A Reporter <reporter@example.org>
```

The subject is `area: summary`, at most 75 characters, in the imperative
("refuse a frame...", not "refused"), with no full stop. It says what
changes, isn't a file name, and isn't reused within a series.

The body is wrapped at 75 columns and written for someone reading `git log`
years later with no context. Say what the change does in plain prose, since
the diff shows how. Don't write "as discussed" or "v2".

Pick the area where most of the change is.

| Area | Covers |
|---|---|
| `codec` | `lib/turborel/protocol/`: frames, fields, the tail, types and values, JSON, compression |
| `transport` | TCP, Unix sockets, named pipes, timeouts |
| `auth` | the mechanisms, SCRAM and its key cache |
| `tls` | TLS, its verification and channel binding |
| `session` | Hello, Ready, Status, notices, conditions, cancel, terminate, ping, reset, change-user |
| `statements` | queries, prepared statements, cursors, describe, completions |
| `lobs` | large objects, their locators and streams |
| `copy` | copy, import and export |
| `settings` | the URI, options, variables, service and password files, several hosts, roles |
| `pipeline` | pipelines |
| `pool` | pools |
| `api` | the plain API and the ActiveRecord adapter |
| `doc` | `doc/`, README.md, RULES.md, CONFORMANCE.md, TODO.md, VERSIONING.md, AGENTS.md, CLAUDE.md, this file |
| `ci` | `.github/`, `.githooks/` |
| `build` | the gemspec, Gemfile, Rakefile, `rakelib/`, and the tools' configurations |

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

`Reported-by:` and `Suggested-by:` may be added without asking. The others
name someone who said so on the record. `git config core.abbrev 12` gives
12-digit hashes, and `git log -1 --pretty='Fixes: %h ("%s")' <commit>` writes
the `Fixes:` line.

No commit or pull request carries AI or agent attribution: no
`Co-Authored-By` for an agent, no "Generated with", and no
`Signed-off-by`.

Stage with an explicit list of paths, `git add -- <path> ...`, never
`git add -A` or `git add .` on the whole tree, so nothing unintended is
committed.

## Pull requests

A pull request is a patch series, and its description is the cover letter.
The template asks for what and why, the series commit by commit, testing,
compatibility and performance. Each commit message still stands alone.

Base it on `main` and keep it rebased, without merging `main` into it. When
revising, rewrite the commits so the series is again what should be merged,
with no "fix review comments" commits. Force-push, and say in a comment what
changed since the last version.

Trailers given in review go into the commits they cover. Drop them from a
commit that later changes substantially, and say so.

Keep a series to about 15 commits. Split a larger one into series that each
stand alone.

## Review

Reviewers check each commit against RULES.md §7's checklist, and that the
manual is updated (R-DOC-6). For
[changes to the protocol's handling](#changes-to-the-protocols-handling),
they also check that the byte-level, TLS and compatibility checks were
done. Review comments are about the change, never the person. A reviewer
who is satisfied gives `Reviewed-by:`.

## Reporting issues

Use the issue forms, **Bug**, **Conformance**, **Performance** or
**Feature**. Try the latest `main` first, and add to an existing issue that
matches rather than opening another.

Reproduce with the smallest program that shows it, with the statements
it runs and the settings it connects with, passwords left out.

State the impact first. Put it in the title's first word when it is severe.

| Tag | Meaning |
|---|---|
| `[WRONG RESULT]` | a value or a row read or sent wrongly |
| `[CRASH]` | an exception that is not a `Turborel::Error`, an abort or a hang |
| `[REGRESSION]` | worked in an earlier commit (give the last good commit and, if you can, the first bad one) |

Give the commit (`git rev-parse --short=12 HEAD`), the Ruby version
(`ruby -v`), the platform and architecture, and the turborel server's
version and commit.

## Security

Don't open a public issue for a vulnerability. Report it privately, as
[SECURITY.md](SECURITY.md) says.

## License

turborel-ruby is under the BSD-2-Clause Plus Patent License in
[LICENSE](LICENSE), and a contribution is made under that license.
Contributors keep their copyright and own their changes. Whoever
submits a change answers for all of it, however it was written.
