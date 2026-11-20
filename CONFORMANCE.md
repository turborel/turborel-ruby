# Conformance

What turborel-ruby implements of turborel's native protocol, version 1,
and of turborel-client's features, row by row, with the choices it made.
The matrix is the same in every turborel driver. It follows the
protocol's page, `doc/client/05-protocol.md`, and turborel-client's two
chapters, `doc/client/02-library.md` and `02-library-connections.md`, in
their order, grouped by the layers of turborel's drivers plan.

A source in brackets is the heading of the page it cites (RULES.md
R-DOC-4): `[PROTOCOL ...]` for the protocol's page, `[CLIENT ...]` for
either chapter. Where the page is silent, the source is turborel's code
or its RULES.md. A row is marked **done** when it is implemented and
tested, and **not yet** until then. Open work is in [TODO.md](TODO.md).

[1 Codec](#1-codec) · [2 Data types](#2-data-types) ·
[3 Values](#3-values) · [4 Requests](#4-requests) ·
[5 Replies](#5-replies) · [6 Capabilities](#6-capabilities) ·
[7 Tail fields](#7-tail-fields) · [8 Transport](#8-transport) ·
[9 Authentication](#9-authentication) · [10 Session](#10-session) ·
[11 Statements](#11-statements) · [12 Large objects](#12-large-objects) ·
[13 Bulk](#13-bulk) · [14 Settings](#14-settings) ·
[15 Throughput](#15-throughput) · [16 Standard API](#16-standard-api) ·
[17 Choices](#17-choices)

---

## 1. Codec

The protocol's encoding, without I/O (`protocol/src/`).

| Item | Source | Status |
|---|---|---|
| The frame header: kind `u8`, length `u32` little-endian, five bytes | [PROTOCOL Frames] | done, `lib/turborel/protocol/frame.rb` |
| A kind the reader does not know, a body cut short, bytes left over: the connection fails (-919, 08006) | [PROTOCOL Frames] | not yet |
| Replies taken up to 16 MiB unless the program says otherwise | [PROTOCOL Frames] | not yet |
| Compressed frames, `z`: a zlib stream, inflated to at most its length, which is at most the longest body taken | [PROTOCOL Compressed frames] | not yet |
| A `z` frame holding a `z` frame, inflating to another length, or not granted: the connection fails | [PROTOCOL Compressed frames] | not yet |
| Fields: `u8`, `u32`, `u64`, `i128`, flag, string, bytes, list, strings, key | [PROTOCOL Values and fields] | not yet |
| A count larger than what follows fails as the body runs out | [PROTOCOL Values and fields] | not yet |
| Composite fields: row, column, parameter, failure | [PROTOCOL Composite fields] | not yet |
| The tail: tags in increasing order; a tag not taken, or not past the last, fails the connection | [PROTOCOL The tail] | not yet |
| Attributes: at most 32, names of 1 to 64 bytes, values of at most 1024 | [PROTOCOL The tail] | not yet |

## 2. Data types

Each type tag, as columns, parameters and the types inside other types write it.

| Item | Source | Status |
|---|---|---|
| Type tag 1, CHARACTER | [PROTOCOL Data types] | not yet |
| Type tag 2, exact numeric | [PROTOCOL Data types] | not yet |
| Type tag 3, approximate numeric | [PROTOCOL Data types] | not yet |
| Type tag 4, a plug-in's type | [PROTOCOL Data types] | not yet |
| Type tag 5, CHARACTER VARYING | [PROTOCOL Data types] | not yet |
| Type tag 6, BINARY | [PROTOCOL Data types] | not yet |
| Type tag 7, BINARY VARYING | [PROTOCOL Data types] | not yet |
| Type tag 8, DATE | [PROTOCOL Data types] | not yet |
| Type tag 9, TIME | [PROTOCOL Data types] | not yet |
| Type tag 10, TIME WITH TIME ZONE | [PROTOCOL Data types] | not yet |
| Type tag 11, TIMESTAMP | [PROTOCOL Data types] | not yet |
| Type tag 12, TIMESTAMP WITH TIME ZONE | [PROTOCOL Data types] | not yet |
| Type tag 13, INTERVAL, each qualifier | [PROTOCOL Data types] | not yet |
| Type tag 14, BOOLEAN | [PROTOCOL Data types] | not yet |
| Type tag 15, DECFLOAT | [PROTOCOL Data types] | not yet |
| Type tag 16, array | [PROTOCOL Data types] | not yet |
| Type tag 17, row | [PROTOCOL Data types] | not yet |
| Type tag 18, CHARACTER LARGE OBJECT | [PROTOCOL Data types] | not yet |
| Type tag 19, BINARY LARGE OBJECT | [PROTOCOL Data types] | not yet |
| Type tag 22, multiset | [PROTOCOL Data types] | not yet |
| Type tag 23, structured type | [PROTOCOL Data types] | not yet |
| Type tag 24, reference type | [PROTOCOL Data types] | not yet |
| Type tag 25, JSON | [PROTOCOL Data types] | not yet |
| Type tag 26, XML, each modifier | [PROTOCOL Data types] | not yet |
| Type tag 27, UUID, with no parameters | turborel RULES.md D184; `protocol/src/fields.rs` | not yet |

## 3. Values

Each value tag, both ways, at its edges.

| Item | Source | Status |
|---|---|---|
| Value tag 0, null | [PROTOCOL Values] | not yet |
| Value tag 1, character string | [PROTOCOL Values] | not yet |
| Value tag 2, exact number, units `i128` and scale, as `BigDecimal` | [PROTOCOL Values] | not yet |
| Value tag 3, approximate number, NaN and -0.0 kept | [PROTOCOL Values] | not yet |
| Value tag 4, a plug-in's value | [PROTOCOL Values] | not yet |
| Value tag 6, binary string | [PROTOCOL Values] | not yet |
| Value tag 8, date | [PROTOCOL Values] | not yet |
| Value tag 9, time | [PROTOCOL Values] | not yet |
| Value tag 11, timestamp, its zone's displacement from -12:59 to +14:00 | [PROTOCOL Values] | not yet |
| Value tag 13, interval | [PROTOCOL Values] | not yet |
| Value tag 14, truth value | [PROTOCOL Values] | not yet |
| Value tag 15, decimal floating point | [PROTOCOL Values] | not yet |
| Value tag 16, array, nested | [PROTOCOL Values] | not yet |
| Value tag 17, row | [PROTOCOL Values] | not yet |
| Value tag 20, large object, whole | [PROTOCOL Values] | not yet |
| Value tag 21, large object, by locator | [PROTOCOL Values] | not yet |
| Value tag 22, multiset | [PROTOCOL Values] | not yet |
| Value tag 23, structured value | [PROTOCOL Values] | not yet |
| Value tag 25, JSON, D89's binary tree decoded to Ruby's JSON values, and parameters encoded into it | turborel RULES.md D89; `src/json/binary.rs` | not yet |
| Value tag 24, reference | [PROTOCOL Values] | not yet |
| Value tag 26, XML, its serialization as CONTENT | [PROTOCOL Values] | not yet |
| Value tag 27, UUID, `bytes` of 16 octets | turborel RULES.md D184; `protocol/src/fields.rs` | not yet |

## 4. Requests

Each request the client sends.

| Item | Source | Status |
|---|---|---|
| Request Hello 'H' | [PROTOCOL Hello 'H'] | not yet |
| Request Answer 'A' | [PROTOCOL Answer 'A'] | not yet |
| Request Query 'Q' | [PROTOCOL Query 'Q'] | not yet |
| Request Prepare 'P' | [PROTOCOL Prepare 'P'] | not yet |
| Request Execute 'E' | [PROTOCOL Execute 'E'] | not yet |
| Request Fetch 'F' | [PROTOCOL Fetch 'F'] | not yet |
| Request Close 'C' | [PROTOCOL Close 'C'] | not yet |
| Request Deallocate 'D' | [PROTOCOL Deallocate 'D'] | not yet |
| Request Lob 'L' | [PROTOCOL Lob 'L'] | not yet |
| Request Cancel 'Z' | [PROTOCOL Cancel 'Z'] | not yet |
| Request Terminate 'X' | [PROTOCOL Terminate 'X'] | not yet |
| Request Describe 'Y' | [PROTOCOL Describe 'Y'] | not yet |
| Request Ping 'G' | [PROTOCOL Ping 'G'] | not yet |
| Request Reset 'W' | [PROTOCOL Reset 'W'] | not yet |
| Request ChangeUser 'U' | [PROTOCOL ChangeUser 'U'] | not yet |
| Request CopyIn 'I' | [PROTOCOL CopyIn 'I'] | not yet |
| Request CopyData 'J' | [PROTOCOL CopyData 'J'] | not yet |
| Request CopyEnd 'N' | [PROTOCOL CopyEnd 'N'] | not yet |

## 5. Replies

Each reply the client reads.

| Item | Source | Status |
|---|---|---|
| Reply Challenge 'C' | [PROTOCOL Challenge 'C'] | not yet |
| Reply Ready 'R' | [PROTOCOL Ready 'R'] | not yet |
| Reply Prepared 'P' | [PROTOCOL Prepared 'P'] | not yet |
| Reply Description 'D' | [PROTOCOL Description 'D'] | not yet |
| Reply Rows 'B' | [PROTOCOL Rows 'B'] | not yet |
| Reply Suspended 'S' | [PROTOCOL Suspended 'S'] | not yet |
| Reply Complete 'K' | [PROTOCOL Complete 'K'] | not yet |
| Reply Error 'E' | [PROTOCOL Error 'E'] | not yet |
| Reply Lob 'L' | [PROTOCOL Lob 'L'] | not yet |
| Reply Notice 'N' | [PROTOCOL Notice 'N'] | not yet |
| Reply Status 'T' | [PROTOCOL Status 'T'] | not yet |
| Reply Pong 'G' | [PROTOCOL Pong 'G'] | not yet |

## 6. Capabilities

Each capability, asked for in Hello and used as granted. A request or tail field of a capability not granted is never sent.

| Item | Source | Status |
|---|---|---|
| Capability `notices` | [PROTOCOL Capabilities] | not yet |
| Capability `status` | [PROTOCOL Capabilities] | not yet |
| Capability `diagnostics` | [PROTOCOL Capabilities] | not yet |
| Capability `describe` | [PROTOCOL Capabilities] | not yet |
| Capability `cursors` | [PROTOCOL Capabilities] | not yet |
| Capability `ping` | [PROTOCOL Capabilities] | not yet |
| Capability `reset` | [PROTOCOL Capabilities] | not yet |
| Capability `change-user` | [PROTOCOL Capabilities] | not yet |
| Capability `query-attributes` | [PROTOCOL Capabilities] | not yet |
| Capability `connection-attributes` | [PROTOCOL Capabilities] | not yet |
| Capability `multi-statement` | [PROTOCOL Capabilities] | not yet |
| Capability `compression` | [PROTOCOL Capabilities] | not yet |
| Capability `commit-position` | [PROTOCOL Capabilities] | not yet |
| Capability `copy` | [PROTOCOL Capabilities] | not yet |
| Capability `row-counts` | [PROTOCOL Capabilities] | not yet |
| Capability `generated-values` | [PROTOCOL Capabilities] | not yet |
| Capability `fetch-ends` | [PROTOCOL Capabilities] | not yet |
| Capability `conditions` | [PROTOCOL Capabilities] | not yet |

## 7. Tail fields

Each tail tag, written or read where its message takes it.

| Item | Source | Status |
|---|---|---|
| Tail tag 1, attributes | [PROTOCOL The tail] | not yet |
| Tail tag 2, multi | [PROTOCOL The tail] | not yet |
| Tail tag 3, cursor | [PROTOCOL The tail] | not yet |
| Tail tag 4, position | [PROTOCOL The tail] | not yet |
| Tail tag 5, more | [PROTOCOL The tail] | not yet |
| Tail tag 6, rows | [PROTOCOL The tail] | not yet |
| Tail tag 7, severity | [PROTOCOL The tail] | not yet |
| Tail tag 8, detail | [PROTOCOL The tail] | not yet |
| Tail tag 9, hint | [PROTOCOL The tail] | not yet |
| Tail tag 10, context | [PROTOCOL The tail] | not yet |
| Tail tag 11, schema | [PROTOCOL The tail] | not yet |
| Tail tag 12, table | [PROTOCOL The tail] | not yet |
| Tail tag 13, column | [PROTOCOL The tail] | not yet |
| Tail tag 14, data type | [PROTOCOL The tail] | not yet |
| Tail tag 15, constraint | [PROTOCOL The tail] | not yet |
| Tail tag 16, generated | [PROTOCOL The tail] | not yet |
| Tail tag 17, conditions | [PROTOCOL The tail] | not yet |
| Tail tag 18, time | [PROTOCOL The tail] | not yet |

## 8. Transport

Where a connection goes (`target.rs`, `timeouts.rs`, `pipe.rs`).

| Item | Source | Status |
|---|---|---|
| TCP, port 7422 unless told another | [PROTOCOL The Native Protocol] | not yet |
| A Unix socket | [CLIENT Connecting] | not yet |
| A Windows named pipe, `\\.\pipe\turborel` | [CLIENT Connecting] | not yet |
| TLS begun on the same port, its first byte 22 | [PROTOCOL The Native Protocol] | not yet |
| Connect timeout, 30 seconds by default, for connecting, TLS and each step of the login | [CLIENT Timeouts] | not yet |
| Read timeout, no limit by default, and changed on a connection | [CLIENT Timeouts] | not yet |
| The longest reply taken, set by the program | [CLIENT Timeouts] | not yet |

## 9. Authentication

How a user is proved (`mechanism.rs`, `scram.rs`, `tls.rs`).

| Item | Source | Status |
|---|---|---|
| Mechanism `trust` | [PROTOCOL Mechanisms] | not yet |
| Mechanism `password`, only over TLS, a Unix socket or a named pipe | [PROTOCOL Mechanisms] | not yet |
| Mechanism `certificate`, the client's certificate presented over TLS | [PROTOCOL Mechanisms] | not yet |
| Mechanism `scram-sha-256`, RFC 5802 and RFC 7677, the server's signature checked | [PROTOCOL Mechanisms] | not yet |
| Mechanism `scram-sha-256-plus` by `tls-exporter`, over TLS 1.3 | [PROTOCOL Mechanisms] | not yet |
| Mechanism `scram-sha-256-plus` by `tls-server-end-point`, over TLS 1.2 | [PROTOCOL Mechanisms] | not yet |
| SCRAM in the clear only where the program says so | [CLIENT Connecting] | not yet |
| `password` and SCRAM refused over plain TCP before connecting (28000) | [CLIENT Connecting] | not yet |
| Trusted authorities: of a file, the platform's, or both | [CLIENT Connecting] | not yet |
| The SCRAM key cache: 64 entries, keyed by salt, iterations and a keyed tag of the password; hits and misses counted; an entry dropped when its login fails | [CLIENT The SCRAM key cache] | not yet |

## 10. Session

A connection's session (`connection.rs`, `session.rs`, `cancel.rs`, `told.rs`).

| Item | Source | Status |
|---|---|---|
| Hello asking for every capability but compression | [CLIENT What a connection asks for] | not yet |
| An offer of the program's own: none, compressed, connection attributes | [CLIENT What a connection asks for] | not yet |
| What was granted; a method needing a capability not granted fails before it sends | [CLIENT What a connection asks for] | not yet |
| Ready: authorization, cancel key, capabilities, the server's product | [PROTOCOL Ready 'R'] | not yet |
| Status at login and as statements change it; a setting read with no round trip, and all of them | [CLIENT What the server tells] | not yet |
| Status names AUTHORIZATION, SCHEMA, READ_ONLY, SERVER_VERSION, SERVER_READ_ONLY, CATALOG and OWNER | `server/src/native/status.rs` | not yet |
| Notices: a handler, or the last 64 kept and taken | [CLIENT What the server tells] | not yet |
| Conditions of the last statement, in its completion | [CLIENT What the server tells] | not yet |
| Diagnostics of a failure: severity, detail, hint, context, schema, table, column, data type, constraint | [CLIENT What the server tells] | not yet |
| A failure's SQLCODE, SQLSTATE, message, rule, position and whether a transaction is active | [PROTOCOL Errors and notices] | not yet |
| in_transaction, as the server said after the last statement | [CLIENT Running statements] | not yet |
| Autocommit, each statement its own transaction by `ends` | [CLIENT Running statements] | not yet |
| Cancel by the key, on a connection of its own, giving up after 10 seconds or a limit of the program's | [CLIENT Running statements] | not yet |
| Terminate, its transaction as SESSION.COMMIT_AT_END says, waiting at most 60 seconds | [CLIENT Connecting] | not yet |
| Ping | [CLIENT Controlling the session] | not yet |
| Reset | [CLIENT Controlling the session] | not yet |
| Change user | [CLIENT Controlling the session] | not yet |
| Query attributes carried by every later statement | [CLIENT Controlling the session] | not yet |
| Several statements in one request, and what each gave | [CLIENT Controlling the session] | not yet |

## 11. Statements

Running statements (`statements.rs`, `frames.rs`).

| Item | Source | Status |
|---|---|---|
| Query: a query's columns and rows, or another statement's completion | [CLIENT Running statements] | not yet |
| A query's rows streamed to the program a batch at a time | [CLIENT Running statements] | not yet |
| Prepare and execute, with the type of each parameter and a query's columns | [CLIENT Prepared statements] | not yet |
| A cursor opened, fetched in batches, and closed | [CLIENT Prepared statements] | not yet |
| Deallocate | [CLIENT Prepared statements] | not yet |
| Numbered cursors, several of one statement open at once | [CLIENT Controlling the session] | not yet |
| Describe a statement, and an open cursor's columns | [CLIENT Controlling the session] | not yet |
| Fetch-ends: under autocommit, a cursor ends its transaction as it ends | [CLIENT What the server tells] | not yet |
| Rows affected | [CLIENT What the server tells] | not yet |
| Generated values | [CLIENT What the server tells] | not yet |
| The server's time: total, queued, locks | [CLIENT What the server tells] | not yet |
| Commit position | [CLIENT What the server tells] | not yet |
| XML values: their text, and parameters made of text | [CLIENT XML values] | not yet |
| UUIDs: their octets and text, and parameters made of either | [CLIENT UUIDs] | not yet |

## 12. Large objects

Large objects (`lobs.rs`).

| Item | Source | Status |
|---|---|---|
| Large objects of at most SERVER.LOB_INLINE_BYTES whole in their rows | [CLIENT Large objects] | not yet |
| Longer ones by locator, with their lengths | [CLIENT Large objects] | not yet |
| Reads of a range by octets or characters, at most 256 KiB at a time | [CLIENT Large objects] | not yet |
| A stream reader that reads one whole, a chunk at a time | [CLIENT Large objects] | not yet |
| Create, and a stream writer whose finish gives the value to pass as a parameter | [CLIENT Large objects] | not yet |
| Append, a character split between writes | [CLIENT Large objects] | not yet |
| Free | [CLIENT Large objects] | not yet |
| Hold past the commit | [CLIENT Large objects] | not yet |

## 13. Bulk

Copy, import and export (`copy.rs`, `import/`, `export.rs`).

| Item | Source | Status |
|---|---|---|
| Copy in: CopyIn, rows sent many to a message, CopyEnd giving the rows inserted | [CLIENT Copying and exporting] | not yet |
| A copy abandoned, as one dropped before it finishes | [CLIENT Copying and exporting] | not yet |
| Copying the rows an iterator gives | [CLIENT Copying and exporting] | not yet |
| Import from a source of headings and records, in bounded memory | [CLIENT Importing] | not yet |
| CSV and tab-separated text, with a header, a delimiter and a text for null | [CLIENT Importing] | not yet |
| Batches committed, 1000 rows by default, and rows that fail skipped if asked | [CLIENT Importing] | not yet |
| An import's failure: where its record began, why, rows committed and rolled back | [CLIENT Importing] | not yet |
| An import by copy where granted and no column is a large object; a field over 64 KiB sent as a large object | [CLIENT Large objects] | not yet |
| Export as CSV, a header then a record for each row | [CLIENT Copying and exporting] | not yet |
| Export as the protocol's frames, and reading them back with every value as it was | [CLIENT Copying and exporting] | not yet |

## 14. Settings

Connecting by settings (`settings/`, `failover.rs`, `role.rs`).

| Item | Source | Status |
|---|---|---|
| Connecting by settings | [CLIENT Connecting by settings] | not yet |
| A password proved by SCRAM, else sent whole; with none, a certificate, else trust | [CLIENT Connecting by settings] | not yet |
| Setting `host` | [CLIENT Where settings come from] | not yet |
| Setting `port` | [CLIENT Where settings come from] | not yet |
| Setting `user` | [CLIENT Where settings come from] | not yet |
| Setting `password` | [CLIENT Where settings come from] | not yet |
| Setting `tls_mode` | [CLIENT Where settings come from] | not yet |
| Setting `channel_binding` | [CLIENT Where settings come from] | not yet |
| Setting `application_name` | [CLIENT Where settings come from] | not yet |
| Setting `connect_timeout` | [CLIENT Where settings come from] | not yet |
| Setting `service` | [CLIENT Where settings come from] | not yet |
| Setting `service_file` | [CLIENT Where settings come from] | not yet |
| Setting `passfile` | [CLIENT Where settings come from] | not yet |
| Setting `target` | [CLIENT Where settings come from] | not yet |
| Setting `load_balance` | [CLIENT Where settings come from] | not yet |
| Setting `tls_roots` | [CLIENT Where settings come from] | not yet |
| Setting `tls_system_roots` | [CLIENT Where settings come from] | not yet |
| Setting `tls_certificate and tls_key` | [CLIENT Where settings come from] | not yet |
| Setting `server_name` | [CLIENT Where settings come from] | not yet |
| Layers: the program's own, the service file's section, the environment, the defaults | [CLIENT Where settings come from] | not yet |
| The environment's variables, TURBOREL_HOST to TURBOREL_PASSFILE, read through a function the program may give | [CLIENT Where settings come from] | not yet |
| Settings refused with 08001: unreadable, no such section, no user | [CLIENT Where settings come from] | not yet |
| The `turborel://` URI, percent-encoded, IPv6 in brackets; another scheme, a path, an unknown setting or a pair without `=` refused | [CLIENT The connection URI] | not yet |
| The service file: sections, comments, a malformed line named by its file and line | [CLIENT The service file] | not yet |
| The password file: `host:port:user:password`, `*` and `\`, the first match, a regular file only | [CLIENT The password file] | not yet |
| Several hosts, tried in order or at random, each address within the connect timeout; the failure naming each | [CLIENT Several servers] | not yet |
| `target` read-write or read-only by SERVER_READ_ONLY, else INFORMATION_SCHEMA.REPLICAS; the role a session sees | [CLIENT Several servers] | not yet |
| TLS modes disable, prefer, require, verify-ca and verify-full; prefer falling back to plain TCP on a failed handshake | [CLIENT TLS by mode] | not yet |
| Channel binding disable, prefer and require | [CLIENT TLS by mode] | not yet |
| The settings' cases of turborel-client's tests | `client/src/settings/tests.rs` | not yet |

## 15. Throughput

Pipelines, pools and the SQL-agent (`pipeline.rs`, `pool/`, `agent.rs`).

| Item | Source | Status |
|---|---|---|
| Pipelines: requests queued and run, one outcome each, in order | [CLIENT Pipelines] | not yet |
| Written a window of 64 KiB at a time, its replies read before the next | [CLIENT Pipelines] | not yet |
| Skip on error: savepoints, the requests after a failure rolled back and skipped | [CLIENT Pipelines] | not yet |
| A pipeline lost, or a skipping batch that cannot be undone, fails whole | [CLIENT Pipelines] | not yet |
| Pools: a bounded set shared by threads; get, and a connection back as it is released | [CLIENT Pools] | not yet |
| PoolConfig `max`, default 10 | [CLIENT Pools] | not yet |
| PoolConfig `max_idle`, default 10 | [CLIENT Pools] | not yet |
| PoolConfig `idle_timeout`, default 10 minutes | [CLIENT Pools] | not yet |
| PoolConfig `max_lifetime`, default 1 hour | [CLIENT Pools] | not yet |
| PoolConfig `wait`, default 30 seconds | [CLIENT Pools] | not yet |
| PoolConfig `check`, default yes | [CLIENT Pools] | not yet |
| PoolConfig `reset`, default none | [CLIENT Pools] | not yet |
| A connection checked by Ping, and reset by Reset as it comes back | [CLIENT Pools] | not yet |
| Of a server that takes neither: ROLLBACK, and the reset as one pipeline | [CLIENT Pools] | not yet |
| get failing with 08001 past `wait`; a pool made of settings or of any source | [CLIENT Pools] | not yet |
| The SQL-agent: named connections, one current; CONNECT, SET CONNECTION and DISCONNECT run by it | [CLIENT The SQL-agent] | not yet |

## 16. Standard API

The language's interface over the layers above (RULES.md D2).

| Item | Source | Status |
|---|---|---|
| The plain API in the manner of the pg gem: connection, `exec`, `exec_params`, `prepare`, results, transactions | RULES.md D2 | not yet |
| The ActiveRecord adapter, for Rails 8.1 and later | RULES.md D2 | not yet |

## 17. Choices

What the driver chose where the protocol or turborel-client leaves a
choice. None is made yet.
