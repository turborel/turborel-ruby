# Versioning

How turborel-ruby's releases are numbered, which protocol each speaks, and
how a release is published.

[Release numbers](#release-numbers) · [Alpha](#alpha) ·
[The protocol](#the-protocol) · [Where the version is](#where-the-version-is) ·
[Publishing](#publishing)

---

## Release numbers

The driver has no version scheme of its own (RULES.md D5). Its version
is the number of the Turborel release it is made for, the same number as
the server's: a Turborel release and each driver's release for it share
it, **MAJOR.MINOR.PATCH**, as Turborel's
[VERSIONING.md](https://github.com/turborel/turborel/blob/main/VERSIONING.md)
numbers them, after
[Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html). What a
release may change follows from its number there, for the driver as for
the server.

A driver of a release works with a server of the same release. A fix of
the driver alone, between Turborel's releases, waits for the next
release's number.

## Alpha

Turborel is in alpha, version **0.0.0**, until its first release, and so
is turborel-ruby. While the version is 0.y.z nothing is promised: the
driver's API, its behaviour and the protocol it speaks may change in any
build. The first stable release is **1.0.0**, with Turborel's.

## The protocol

The alpha speaks the native protocol's version 1, the only version. It
grows by capabilities, never by a new version: the driver asks for the
capabilities it implements, and the server grants those it has, so a
driver and a server of different builds agree on what both have. The
driver sends version 1 in its Hello, and a server that does not speak it
refuses the connection (SQLSTATE 08004).

| Driver | Turborel | Protocol |
|---|---|---|
| 0.0.0 (alpha) | 0.0.0 (alpha) | 1 |

## Where the version is

- `Turborel::VERSION`, in `lib/turborel/version.rb` holds the number, written once. Everything else
  that carries it, the package's metadata and what the library tells a
  program, takes it from there or is held to it by a test.
- A release is tagged `v` and its number, as `v0.0.0`. turborel.com's
  documentation site reads the manual, `doc/`, from `main` while there
  is no release, and at each release's tag once there are.

## Publishing

Nothing is published to RubyGems, and no release is tagged, until
every Turborel driver is done. Then the owner publishes them together,
each to its language's registry. Until then, build from source, as
[README.md](README.md) says.

A release is published by the owner alone, from a clean checkout of a
pushed commit that has passed `bundle exec rake verify` and
`bundle exec rake coverage` in CI on every platform:

1. Set the release's number in `Turborel::VERSION`, in `lib/turborel/version.rb`, in a commit of its
   own.
2. Run the workflow **release** by hand, on that commit. It builds the
   package and checks it, and keeps what it built as the run's
   artifacts. It publishes nothing.
3. The workflow's last step, which tags the release and publishes it, is
   written but disabled until the owner enables it and gives it what the
   registry needs to accept the release. Every package carries
   `LICENSE`.

A version published to a registry can be withdrawn from new installs at
most, never published again with other contents. A fix is a new
release.
