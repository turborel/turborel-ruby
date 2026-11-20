# Security

Report a vulnerability privately, never in a public issue: on the
repository's **Security** tab, choose **Report a vulnerability**. Only the
maintainers see the report.

What counts, for a driver:

- TLS not used, or not verified, where it was asked for: a `tls_mode` of
  `require`, `verify-ca` or `verify-full`, or a `channel_binding` of
  `require`, that connects without it, or falls back to less than it
  asked without saying so;
- a server's SCRAM signature not checked, or SCRAM-SHA-256-PLUS's
  channel binding left out where it was asked for;
- a password, anything derived from one such as a SCRAM key or proof, or
  a session's cancel key, disclosed: sent where it should not go, as a
  secret over plain TCP, written to a log or a failure's message, shown
  by the language's display of an object, or kept where another program
  can read it;
- a server's reply, bytes in the middle of the connection, or a file the
  driver reads (a service file, a password file, an export), that can
  crash the program, run code in it, or take its memory without bound.

A wrong value, a lost connection with no attacker, or a crash only the
program's own misuse of the API can cause is a bug: report it with the
**Bug** form, its impact in the title (CONTRIBUTING.md, Reporting
issues). A vulnerability of the server goes to
[turborel](https://github.com/turborel/turborel/security), and one of a
library turborel-ruby is built on, to that library's repository.

Say in the report:

- what an attacker needs, such as a server of their own, a place on the
  network between the program and the server, a user, or a file the
  driver reads;
- what they gain;
- the commit you tested (`git rev-parse --short=12 HEAD`), the runtime
  or compiler and its version, and the platform;
- the smallest steps that show it.

You will hear back within a week. The fix is made in private and
published with an advisory that credits you, unless you ask not to be
named.
