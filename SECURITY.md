# Security

Report a vulnerability privately, never in a public issue: on the
repository's **Security** tab, choose **Report a vulnerability**. Only the
maintainers see the report.

What counts, for a driver:

- TLS not used, or not verified, where it was asked for: a `tls_mode`
  of `require`, `verify-ca` or `verify-full`, or a `channel_binding` of
  `require`, that connects without it;
- a password, a SCRAM key, or anything derived from a password, or a
  cancel key, disclosed: sent where it should not go, as a secret over
  plain TCP, or shown in an error, a log or an `inspect`;
- a server's reply, or a file the driver reads, that can crash the
  client, run code in it, or take its memory without bound.

A wrong result, a lost connection with no attacker, or a crash only the
program's own code can cause is a bug: report it with the **Bug** form,
its impact in the title (CONTRIBUTING.md, Reporting issues).

Say in the report:

- what an attacker needs, such as a server of their own, a place on the
  network, or a file the driver reads;
- what they gain;
- the commit you tested (`git rev-parse --short=12 HEAD`);
- the smallest steps that show it.

You will hear back within a week. The fix is made in private and
published with an advisory that credits you, unless you ask not to be
named.
