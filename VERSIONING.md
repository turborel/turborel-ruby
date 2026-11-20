# Versioning

How turborel-ruby's releases are numbered, which protocol each speaks, and
how the gem is published.

[Release numbers](#release-numbers) · [Alpha](#alpha) ·
[The protocol](#the-protocol) · [Where the version is](#where-the-version-is) ·
[Publishing](#publishing)

---

## Release numbers

The driver has no version scheme of its own (RULES.md D12). Its version
is the number of the turborel release it is made for, the same number as
the server's: a turborel release and each driver's release share it. What
each kind of release may change is turborel's
[VERSIONING.md](https://github.com/turborel/turborel/blob/main/VERSIONING.md)'s
to say, and holds for the driver of the same number.

## Alpha

turborel is in alpha, version **0.0.0**, and so is the driver. While the
version is 0.y.z nothing is promised: the driver's API, its behaviour and
the protocol may change in any build.

## The protocol

The alpha speaks the native protocol's version 1, the only version
(`doc/client/05-protocol.md` in turborel's repository). The protocol grows
by capabilities, which a client asks for and a server grants, never by a
new version, so a driver and a server of the same release always work
together.

## Where the version is

- `Turborel::VERSION`, in `lib/turborel/version.rb`, is the number, and
  the gemspec takes it from there.

## Publishing

The gem goes to [RubyGems](https://rubygems.org) as `turborel`, and only
once every turborel driver is done; the owner publishes it, from a
rubygems.org account with multi-factor authentication, which the gemspec
requires (`rubygems_mfa_required`). Until then nothing is published.

A release is published from a clean checkout of a pushed commit that has
passed `bundle exec rake verify` and `bundle exec rake coverage`:

```
bundle exec rake build       # pkg/turborel-<version>.gem
gem push pkg/turborel-<version>.gem
```

The release workflow (`.github/workflows/release.yml`), run by hand,
builds and checks the gem on CI and keeps it as the run's artifact. Its
publishing step is written but disabled, until the owner enables it. A
published version can be yanked, so no new install takes it, but it
cannot be published again. A fix is a new release.
