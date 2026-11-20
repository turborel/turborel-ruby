# TODO

Open work, by milestone. Each item says what is missing. How the driver
is built is in [RULES.md](RULES.md), and what is implemented, row by row,
is in [CONFORMANCE.md](CONFORMANCE.md). Finished work leaves this file,
and git keeps its history. The driver is done when this file is empty.

Code never cites this file (R-DOC-5).

[M1 Codec](#m1-codec) · [M2 Connect](#m2-connect) ·
[M3 Statements](#m3-statements) ·
[M4 Large objects and bulk](#m4-large-objects-and-bulk) ·
[M5 Settings](#m5-settings) · [M6 Throughput](#m6-throughput) ·
[M7 Standard API](#m7-standard-api) · [M8 Parity audit](#m8-parity-audit)

---

## M1 Codec

The protocol's encoding, without I/O, each part with its codec tests from
the page.

- Frames: reading a frame whole, a kind the reader does not know, a body
  cut short and bytes left over failing the connection.
- Fields: `u8`, `u32`, `u64`, `i128`, flag, string, bytes, list, key;
  counts checked against what remains.
- The tail: tags in increasing order, a tag a message does not take or
  one out of order failing the connection; the 32 attributes and their
  lengths.
- The data types, tags 1 to 27, UUID's 27 among them.
- The values, tags 0 to 27, at their edges: `i128` limits and scales,
  NaN and -0.0, DECFLOAT, each interval qualifier, displacements from
  -12:59 to +14:00, nested arrays, rows, multisets and structured values,
  locators, each XML modifier, UUID's 16 octets; exact numbers as
  `BigDecimal`.
- JSON values, tag 25, as RULES.md D89 of turborel lays out the binary
  tree: decoded to Ruby's JSON values, and parameters encoded into it.
- The composite fields: row, column, parameter, failure.
- Every request encoded and every reply decoded.
- Compressed frames, `z`, zlib, inflating at most the length given.

## M2 Connect

- TCP on port 7422, a Unix socket, and on Windows the named pipe
  `\\.\pipe\turborel`.
- TLS begun on the same port, verifying the server's certificate and
  name as asked.
- The mechanisms `trust`, `password`, `certificate`, `scram-sha-256` and
  `scram-sha-256-plus`, by `tls-exporter` on TLS 1.3 and
  `tls-server-end-point` on TLS 1.2; a secret refused over plain TCP
  (SQLSTATE 28000).
- The SCRAM key cache: 64 entries, keyed by salt, iterations and a tag
  of the password under a secret of the cache's own.
- Hello asking for every capability but compression; Ready; Status at
  login, with SERVER_READ_ONLY, CATALOG and OWNER besides the page's
  names.
- Timeouts: connect, 30 seconds by default; read, no limit by default;
  the longest reply taken.
- Terminate, waiting at most 60 seconds; cancel by the key on a
  connection of its own, giving up after 10 seconds.
- Live tests against `ghcr.io/turborel/turborel:nightly` in CI, with test
  certificates, SCRAM users and TRUST_LOCAL, set up in `test/server/`;
  SCRAM checked by RFC 7677's test vector.

## M3 Statements

- Query and a query's rows streamed a batch at a time.
- Prepare, Execute, Fetch, Close, Deallocate; numbered cursors;
  Describe of a statement and of a cursor.
- Failures with diagnostics; notices, the last 64 kept or given to a
  handler; conditions.
- Autocommit by `ends`; `fetch-ends`; in_transaction.
- Completion details: rows affected, generated values, server time,
  commit position.
- Multi-statement queries; query and connection attributes; Ping, Reset,
  ChangeUser.

## M4 Large objects and bulk

- Large objects whole and by locator; reads in 256 KiB chunks by octets
  or characters; create, append, free and hold; a stream reader and
  writer.
- Copy: CopyIn, CopyData, CopyEnd, and abandoning a copy.
- Import of CSV and tab-separated text, in batches, skipping rows that
  fail if asked; a field longer than 64 KiB sent as a large object.
- Export as CSV and as the protocol's frames, and reading the latter
  back.

## M5 Settings

- The `turborel://` URI, options set by the program, the `TURBOREL_*`
  variables, the service file and the password file, in their layers,
  tested by the cases of turborel-client's `client/src/settings/tests.rs`.
- Several hosts, each address tried within the connect timeout;
  `load_balance`; `target` of `read-write` or `read-only`.
- `tls_mode`, its five modes; `channel_binding`; `application_name` as
  the connection attribute `application`.

## M6 Throughput

- Pipelines, written a 64 KiB window at a time, skipping on error by
  savepoints.
- Pools, with PoolConfig's defaults, a Ping check, and a Reset as each
  connection comes back.
- The SQL-agent: CONNECT, SET CONNECTION and DISCONNECT.

## M7 Standard API

- The plain API in the manner of the pg gem: connection, `exec`,
  `exec_params`, `prepare`, results, transactions (RULES.md D2).
- The ActiveRecord adapter for Rails 8.1 and later, under
  `active_record/connection_adapters/turborel_adapter` (D2).
- The manual, `doc/`, every example run.

## M8 Parity audit

- Every row of CONFORMANCE.md checked against turborel-client and the
  protocol's page, each marked done.
- The coverage floors held, and raised where coverage rose.
- This file empty.
