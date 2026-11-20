# Conformance

What turborel-ruby implements of Turborel's native protocol, version 1, and
of turborel-client's features, row by row. This is the parity matrix
every Turborel driver keeps: the same rows, with the same IDs, in the
same order, so one driver is checked against another and each against
turborel-client. A driver is done when every row is.

The rows come from three of Turborel's documents, in their order: the
protocol, `doc/client/05-protocol.md`; the client library,
`doc/client/02-library.md`; and its settings, pipelines and pools,
`doc/client/02-library-connections.md`. Each section here is one of
theirs, and each row cites its heading as the tests cite it (RULES.md
D6). The headings are those of Turborel's main at e4f08f77. Last come
the rows of this driver's standard API (RULES.md D2).

**Done** means the driver's code for the row exists and is tested by
tests that cite the row's section (RULES.md R-TRACE-4). **Not yet**
means it is not. A row changes in the commit that implements it. A
driver built over another, as turborel-cpp is over turborel-c, marks a
row of the codec (the P-FRAME, P-ZFRAME, P-FIELD, P-TYPE, P-VAL, P-JSON,
P-COMP and P-TAIL rows) **done by turborel-c** once the release of it the
driver builds with marks the row done, and any other row done once its
own API gives it and its own tests show it.

An ID never changes and is never reused; a row added later takes the
next free number of its section. Rows of a data type, a value or a tail
field are numbered by their tag, and the other rows of those sections
from 100. [TODO.md](TODO.md) gives the milestone of each row.

Contents: [Where the page and the code differ](#where-the-page-and-the-code-differ) ·
[Summary](#summary) · [The protocol](#the-protocol) ·
[The client library](#the-client-library) ·
[Settings, pipelines and pools](#settings-pipelines-and-pools) ·
[The standard API](#the-standard-api)

---

## Where the page and the code differ

Where The Native Protocol and turborel-protocol's code differ, the code
is right, and the rows follow it. At e4f08f77 the page leaves out three
things the code does:

| Gap | The code | Rows |
|---|---|---|
| G1 | UUID is type tag 27, with no parameters, and value tag 27, whose body is bytes: a `u32` count of 16, then the 16 octets (Turborel's RULES.md D184, `protocol/src/fields.rs`) | P-TYPE-27, P-VAL-27 |
| G2 | Besides AUTHORIZATION, SCHEMA, READ_ONLY and SERVER_VERSION, the server tells SERVER_READ_ONLY (YES or NO, how a client tells a replica from a primary), CATALOG and OWNER (YES or NO) (`server/src/native/status.rs`) | P-STATUS-7 to P-STATUS-9 |
| G3 | A JSON value, tag 25, carries the binary tree of Turborel's RULES.md D89 (`src/json/binary.rs`, `src/json/binary/write.rs`) | P-VAL-25, the P-JSON rows |

---

## Summary

The same in every driver; the status of each row is in its table.

| Part | Rows |
|---|---|
| The protocol | 241 |
| The client library | 92 |
| Settings, pipelines and pools | 82 |
| All but the standard API | 415 |

---

## The protocol

From `doc/client/05-protocol.md`, The Native Protocol.

### The page's opening

| ID | Row | Citation | Status |
|---|---|---|---|
| P-INTRO-1 | TCP, on port 7422 unless told another | `[PROTOCOL The Native Protocol]` | not yet |
| P-INTRO-2 | A Unix socket, or a named pipe, where the operator asks | `[PROTOCOL The Native Protocol]` | not yet |
| P-INTRO-3 | TLS begun on the same port, the server telling it by the handshake's first byte, 22 | `[PROTOCOL The Native Protocol]` | not yet |
| P-INTRO-4 | Version 1, grown by capabilities alone; a client that asks for none sees the first form, byte for byte | `[PROTOCOL The Native Protocol]` | not yet |

### Frames

| ID | Row | Citation | Status |
|---|---|---|---|
| P-FRAME-1 | The header: kind `u8`, then the body's length `u32` little-endian, the header not counted; written and read | `[PROTOCOL Frames]` | done |
| P-FRAME-2 | A kind read in the direction it travels: `C` from a client is Close, from the server Challenge | `[PROTOCOL Frames]` | not yet |
| P-FRAME-3 | A kind the reader does not know fails the connection (SQLCODE -919, SQLSTATE 08006) | `[PROTOCOL Frames]` | not yet |
| P-FRAME-4 | A body cut short fails the connection | `[PROTOCOL Frames]` | done |
| P-FRAME-5 | Bytes left over after a message's last field fail the connection | `[PROTOCOL Frames]` | done |
| P-FRAME-6 | Replies taken up to 16 MiB of body unless the program says otherwise; a longer one fails the connection | `[PROTOCOL Frames]` | done |

### Compressed frames

| ID | Row | Citation | Status |
|---|---|---|---|
| P-ZFRAME-1 | A frame sent compressed as kind `z`, once `compression` is granted: the held frame's kind, its body's length, a zlib stream of the body | `[PROTOCOL Compressed frames]` | done |
| P-ZFRAME-2 | A threshold of the client's own for compressing, a frame sent as it is where compressing would not shorten it | `[PROTOCOL Compressed frames]` | done |
| P-ZFRAME-3 | A `z` frame received inflated to at most its `length`, itself at most the longest body taken | `[PROTOCOL Compressed frames]` | done |
| P-ZFRAME-4 | A `z` frame holding another `z` frame fails the connection | `[PROTOCOL Compressed frames]` | done |
| P-ZFRAME-5 | A `z` frame that inflates to another length fails the connection | `[PROTOCOL Compressed frames]` | done |
| P-ZFRAME-6 | A `z` frame received when `compression` was not granted fails the connection | `[PROTOCOL Compressed frames]` | not yet |

### Values and fields

| ID | Row | Citation | Status |
|---|---|---|---|
| P-FIELD-1 | `u8`, `u32` and `u64`, least significant byte first | `[PROTOCOL Values and fields]` | done |
| P-FIELD-2 | `i32 as u32` and `i64 as u64`, a signed number's bits in an unsigned field of its size | `[PROTOCOL Values and fields]` | done |
| P-FIELD-3 | `i128`, 16 bytes, two's complement, least significant first | `[PROTOCOL Values and fields]` | done |
| P-FIELD-4 | flag: `u8`, 0 or 1; any other byte fails the connection | `[PROTOCOL Values and fields]` | done |
| P-FIELD-5 | string: its length in bytes, `u32`, then its UTF-8 | `[PROTOCOL Values and fields]` | done |
| P-FIELD-6 | bytes: its length, `u32`, then the bytes | `[PROTOCOL Values and fields]` | done |
| P-FIELD-7 | list: its count, `u32`, then each item; strings, a list of strings | `[PROTOCOL Values and fields]` | done |
| P-FIELD-8 | key: 16 bytes, with no length before them | `[PROTOCOL Values and fields]` | not yet |
| P-FIELD-9 | A count larger than what follows fails as the body runs out, reserving no memory for it | `[PROTOCOL Values and fields]` | done |

### Data types

| ID | Row | Citation | Status |
|---|---|---|---|
| P-TYPE-1 | 1 CHARACTER: length `u32`, units `u8` (0 characters, 1 octets) | `[PROTOCOL Data types]` | not yet |
| P-TYPE-2 | 2 exact numeric: precision `u32`, scale `u32` | `[PROTOCOL Data types]` | not yet |
| P-TYPE-3 | 3 approximate numeric: precision `u32` | `[PROTOCOL Data types]` | not yet |
| P-TYPE-4 | 4 a plug-in's type: its name, its parameters as a list of `u32` | `[PROTOCOL Data types]` | not yet |
| P-TYPE-5 | 5 CHARACTER VARYING: length `u32`, units `u8` | `[PROTOCOL Data types]` | not yet |
| P-TYPE-6 | 6 BINARY: length `u32` | `[PROTOCOL Data types]` | not yet |
| P-TYPE-7 | 7 BINARY VARYING: length `u32` | `[PROTOCOL Data types]` | not yet |
| P-TYPE-8 | 8 DATE: precision `u32` | `[PROTOCOL Data types]` | not yet |
| P-TYPE-9 | 9 TIME: precision `u32` | `[PROTOCOL Data types]` | not yet |
| P-TYPE-10 | 10 TIME WITH TIME ZONE: precision `u32` | `[PROTOCOL Data types]` | not yet |
| P-TYPE-11 | 11 TIMESTAMP: precision `u32` | `[PROTOCOL Data types]` | not yet |
| P-TYPE-12 | 12 TIMESTAMP WITH TIME ZONE: precision `u32` | `[PROTOCOL Data types]` | not yet |
| P-TYPE-13 | 13 INTERVAL: start field, end field, leading precision, fractional precision, each `u32`; fields 0 YEAR, 1 MONTH, 2 DAY, 3 HOUR, 4 MINUTE, 5 SECOND | `[PROTOCOL Data types]` | not yet |
| P-TYPE-14 | 14 BOOLEAN: nothing | `[PROTOCOL Data types]` | not yet |
| P-TYPE-15 | 15 DECFLOAT: precision `u32` | `[PROTOCOL Data types]` | not yet |
| P-TYPE-16 | 16 array: maximum cardinality `u32`, then the element type | `[PROTOCOL Data types]` | not yet |
| P-TYPE-17 | 17 row: a list of each field's name, then its type | `[PROTOCOL Data types]` | not yet |
| P-TYPE-18 | 18 CHARACTER LARGE OBJECT: length `u64`, units `u8` | `[PROTOCOL Data types]` | not yet |
| P-TYPE-19 | 19 BINARY LARGE OBJECT: length `u64`, units `u8` | `[PROTOCOL Data types]` | not yet |
| P-TYPE-22 | 22 multiset: the element type | `[PROTOCOL Data types]` | not yet |
| P-TYPE-23 | 23 structured type: its schema and name; its proper supertypes, each schema and name | `[PROTOCOL Data types]` | not yet |
| P-TYPE-24 | 24 reference type: the referenced type's names; scoped `u8`, and if 1 the scope's schema and name | `[PROTOCOL Data types]` | not yet |
| P-TYPE-25 | 25 JSON: nothing | `[PROTOCOL Data types]` | not yet |
| P-TYPE-26 | 26 XML: primary modifier `u8` (DOCUMENT, CONTENT, SEQUENCE), secondary `u8` (UNTYPED, ANY, XMLSCHEMA); of XMLSCHEMA, the schema's schema and name, its namespace and its element | `[PROTOCOL Data types]` | not yet |
| P-TYPE-27 | 27 UUID: nothing (gap G1) | `[PROTOCOL Data types]` | not yet |
| P-TYPE-100 | A distinct type written as its source type | `[PROTOCOL Data types]` | not yet |
| P-TYPE-101 | A plug-in's type the client does not have read by its name, its values shown by their text | `[PROTOCOL Data types]` | not yet |

### Values

| ID | Row | Citation | Status |
|---|---|---|---|
| P-VAL-0 | 0 null: nothing | `[PROTOCOL Values]` | not yet |
| P-VAL-1 | 1 character string: string, of a CHARACTER or a CHARACTER VARYING column alike | `[PROTOCOL Values]` | not yet |
| P-VAL-2 | 2 exact number: units `i128`, then scale `u32`, units divided by ten to the scale; at the limits of `i128` and of scale | `[PROTOCOL Values]` | not yet |
| P-VAL-3 | 3 approximate number: an IEEE 754 double's bits, `u64`; NaN and -0.0 kept | `[PROTOCOL Values]` | not yet |
| P-VAL-4 | 4 a plug-in's value: its type's name, its text, its bytes | `[PROTOCOL Values]` | not yet |
| P-VAL-6 | 6 binary string: bytes | `[PROTOCOL Values]` | not yet |
| P-VAL-8 | 8 date, written as a timestamp | `[PROTOCOL Values]` | not yet |
| P-VAL-9 | 9 time, written as a timestamp | `[PROTOCOL Values]` | not yet |
| P-VAL-11 | 11 timestamp: zoned `u8`; precision `u8`; the displacement in minutes, an `i16` in the low half of a `u32`, -12:59 to +14:00; the instant, microseconds in UTC, `i64 as u64` | `[PROTOCOL Values]` | not yet |
| P-VAL-13 | 13 interval: its qualifier as the INTERVAL type writes it, then units `i128`, months or microseconds; every qualifier | `[PROTOCOL Values]` | not yet |
| P-VAL-14 | 14 truth value: `u8`, 0 false, 1 true; unknown as null | `[PROTOCOL Values]` | not yet |
| P-VAL-15 | 15 decimal floating point: coefficient `i128`, then exponent `i32 as u32` | `[PROTOCOL Values]` | not yet |
| P-VAL-16 | 16 array: a list of values, nested | `[PROTOCOL Values]` | not yet |
| P-VAL-17 | 17 row: a list of values, one for each field | `[PROTOCOL Values]` | not yet |
| P-VAL-20 | 20 large object, whole: kind `u8` (0 character, 1 binary), then its octets | `[PROTOCOL Values]` | not yet |
| P-VAL-21 | 21 large object, by locator: kind `u8`, locator `u32`, its octets `u64`, its characters `u64` | `[PROTOCOL Values]` | not yet |
| P-VAL-22 | 22 multiset: a list of values, in no set order | `[PROTOCOL Values]` | not yet |
| P-VAL-23 | 23 structured value: its most specific type's schema and name, then its attributes | `[PROTOCOL Values]` | not yet |
| P-VAL-24 | 24 reference: bytes | `[PROTOCOL Values]` | not yet |
| P-VAL-25 | 25 JSON: bytes, the binary tree of Turborel's RULES.md D89 (gap G3), read to the language's JSON value or text and written from one; its nodes are the P-JSON rows | `[PROTOCOL Values]` | not yet |
| P-VAL-26 | 26 XML: its serialization as CONTENT, string | `[PROTOCOL Values]` | not yet |
| P-VAL-27 | 27 UUID: bytes, a count of 16, then the 16 octets (gap G1) | `[PROTOCOL Values]` | not yet |
| P-VAL-100 | A value's tag says how it is written, not its column's type: CHARACTER VARYING written with tag 1 | `[PROTOCOL Values]` | not yet |
| P-VAL-101 | A datetime's zoned byte 1 for a type WITH TIME ZONE; without a zone, the displacement the value is shown in | `[PROTOCOL Values]` | not yet |
| P-VAL-102 | A large object of at most SERVER.LOB_INLINE_BYTES, 64 KiB by default, read whole; a longer one by its locator, valid until its transaction ends | `[PROTOCOL Values]` | not yet |
| P-VAL-103 | A large object sent whole, or as a locator the client made with Lob requests | `[PROTOCOL Values]` | not yet |

### JSON values

Gap G3: the page gives a JSON value's body as "its stored form".
These rows follow Turborel's RULES.md D89 and `src/json/binary.rs`,
cited under the page's section on values.

| ID | Row | Citation | Status |
|---|---|---|---|
| P-JSON-0 | Node 0 null | `[PROTOCOL Values]` | not yet |
| P-JSON-1 | Node 1 false | `[PROTOCOL Values]` | not yet |
| P-JSON-2 | Node 2 true | `[PROTOCOL Values]` | not yet |
| P-JSON-3 | Node 3 integer: `i64` | `[PROTOCOL Values]` | not yet |
| P-JSON-4 | Node 4 decimal: units `i64`, scale `u8` | `[PROTOCOL Values]` | not yet |
| P-JSON-5 | Node 5 wide decimal: units `i128`, scale `u32` | `[PROTOCOL Values]` | not yet |
| P-JSON-6 | Node 6 decimal floating point: coefficient `i128`, exponent `i32` | `[PROTOCOL Values]` | not yet |
| P-JSON-7 | Node 7 approximate: `f64` bits | `[PROTOCOL Values]` | not yet |
| P-JSON-8 | Node 8 string: octets `u32`, UTF-8 | `[PROTOCOL Values]` | not yet |
| P-JSON-9 | Node 9 datetime: moment `u8` (date, time, timestamp), UTC `i64`, zone minutes `i16`, zoned `u8`, precision `u8` | `[PROTOCOL Values]` | not yet |
| P-JSON-10 | Node 10 array: count `u32`, size `u32`, an offset `u32` of each element, the elements | `[PROTOCOL Values]` | not yet |
| P-JSON-11 | Node 11 object: count `u32`, size `u32`, an offset `u32` of each member in key order, the members in written order, each key and value | `[PROTOCOL Values]` | not yet |
| P-JSON-100 | A document: a version octet, 1, then its root node; another version refused | `[PROTOCOL Values]` | not yet |
| P-JSON-101 | An object's directory sorted by key octets, members of one key in written order; written order kept | `[PROTOCOL Values]` | not yet |

### Composite fields

| ID | Row | Citation | Status |
|---|---|---|---|
| P-COMP-1 | row: a list of values | `[PROTOCOL Composite fields]` | not yet |
| P-COMP-2 | column: named flag; its name, if named; data type; not null flag | `[PROTOCOL Composite fields]` | not yet |
| P-COMP-3 | parameter: varying flag, 1 where the server gives CHARACTER VARYING of the longest length; data type | `[PROTOCOL Composite fields]` | not yet |
| P-COMP-4 | failure: SQLCODE `i32 as u32`; SQLSTATE, 5 characters; message; cited flag and the rule; placed flag and the position, in characters; active flag; tail 7 to 15 | `[PROTOCOL Composite fields]` | not yet |

### The tail

| ID | Row | Citation | Status |
|---|---|---|---|
| P-TAIL-1 | 1 attributes, on Hello, Query and Execute: a count, then each name and value | `[PROTOCOL The tail]` | not yet |
| P-TAIL-2 | 2 multi, on Query | `[PROTOCOL The tail]` | not yet |
| P-TAIL-3 | 3 cursor, `u32`, on Execute, Fetch and Close | `[PROTOCOL The tail]` | not yet |
| P-TAIL-4 | 4 position, `u64`, on Complete | `[PROTOCOL The tail]` | not yet |
| P-TAIL-5 | 5 more, on Complete | `[PROTOCOL The tail]` | not yet |
| P-TAIL-6 | 6 rows, `u64`, on Complete | `[PROTOCOL The tail]` | not yet |
| P-TAIL-7 | 7 severity, on a failure and Notice | `[PROTOCOL The tail]` | not yet |
| P-TAIL-8 | 8 detail, on a failure and Notice | `[PROTOCOL The tail]` | not yet |
| P-TAIL-9 | 9 hint, on a failure and Notice | `[PROTOCOL The tail]` | not yet |
| P-TAIL-10 | 10 context, on a failure and Notice | `[PROTOCOL The tail]` | not yet |
| P-TAIL-11 | 11 schema, on a failure and Notice | `[PROTOCOL The tail]` | not yet |
| P-TAIL-12 | 12 table, on a failure and Notice | `[PROTOCOL The tail]` | not yet |
| P-TAIL-13 | 13 column, on a failure and Notice | `[PROTOCOL The tail]` | not yet |
| P-TAIL-14 | 14 data type, on a failure and Notice | `[PROTOCOL The tail]` | not yet |
| P-TAIL-15 | 15 constraint, on a failure and Notice | `[PROTOCOL The tail]` | not yet |
| P-TAIL-16 | 16 generated, a list of strings, on Complete | `[PROTOCOL The tail]` | not yet |
| P-TAIL-17 | 17 conditions, a list of failures as bytes, on Complete | `[PROTOCOL The tail]` | not yet |
| P-TAIL-18 | 18 time, total, queued and locks, each `u64`, on Complete | `[PROTOCOL The tail]` | not yet |
| P-TAIL-100 | Tags in increasing order; a tag the message does not take, or one not past the last, fails the connection | `[PROTOCOL The tail]` | not yet |
| P-TAIL-101 | A field written only where its capability was granted; a message with an empty tail is its first form exactly | `[PROTOCOL The tail]` | not yet |
| P-TAIL-102 | At most 32 attributes, a name of 1 to 64 bytes, a value of at most 1024; more fails the connection | `[PROTOCOL The tail]` | not yet |

### Opening a connection

| ID | Row | Citation | Status |
|---|---|---|---|
| P-OPEN-1 | A connection's first message is Hello, or Cancel | `[PROTOCOL Opening a connection]` | not yet |
| P-OPEN-2 | Challenge and Answer, step by step, until the server accepts or refuses | `[PROTOCOL Opening a connection]` | not yet |
| P-OPEN-3 | Refused: an Error, and the server closes | `[PROTOCOL Opening a connection]` | not yet |
| P-OPEN-4 | Accepted: a Status for each session setting, with `status`, then Ready | `[PROTOCOL Opening a connection]` | not yet |
| P-OPEN-5 | The capabilities granted read from Ready, those asked for that the server has, in the table's order | `[PROTOCOL Opening a connection]` | not yet |
| P-OPEN-6 | Ready at login never compressed; compression begins after it | `[PROTOCOL Opening a connection]` | not yet |
| P-OPEN-7 | A version other than 1 refused (SQLSTATE 08004) | `[PROTOCOL Opening a connection]` | not yet |
| P-OPEN-8 | A user name not an identifier, or a mechanism not served, refused before any exchange (SQLSTATE 28000) | `[PROTOCOL Opening a connection]` | not yet |

### Mechanisms

| ID | Row | Citation | Status |
|---|---|---|---|
| P-MECH-1 | `trust`, accepted at once | `[PROTOCOL Mechanisms]` | not yet |
| P-MECH-2 | `password`, the password's UTF-8, only over TLS, a Unix socket or a named pipe | `[PROTOCOL Mechanisms]` | not yet |
| P-MECH-3 | `certificate`, by the TLS client certificate's common name | `[PROTOCOL Mechanisms]` | not yet |
| P-MECH-4 | `scram-sha-256`: client-first in Hello, server-first, client-final, server-final, an empty Answer (RFC 5802, RFC 7677) | `[PROTOCOL Mechanisms]` | not yet |
| P-MECH-5 | The server's SCRAM signature checked before the last, empty Answer | `[PROTOCOL Mechanisms]` | not yet |
| P-MECH-6 | `scram-sha-256-plus` bound by `tls-exporter`, as its GS2 header names | `[PROTOCOL Mechanisms]` | not yet |
| P-MECH-7 | `scram-sha-256-plus` bound by `tls-server-end-point`, as its GS2 header names | `[PROTOCOL Mechanisms]` | not yet |

### Capabilities

| ID | Row | Citation | Status |
|---|---|---|---|
| P-CAP-1 | `notices` | `[PROTOCOL Capabilities]` | not yet |
| P-CAP-2 | `status` | `[PROTOCOL Capabilities]` | not yet |
| P-CAP-3 | `diagnostics` | `[PROTOCOL Capabilities]` | not yet |
| P-CAP-4 | `describe` | `[PROTOCOL Capabilities]` | not yet |
| P-CAP-5 | `cursors` | `[PROTOCOL Capabilities]` | not yet |
| P-CAP-6 | `ping` | `[PROTOCOL Capabilities]` | not yet |
| P-CAP-7 | `reset` | `[PROTOCOL Capabilities]` | not yet |
| P-CAP-8 | `change-user` | `[PROTOCOL Capabilities]` | not yet |
| P-CAP-9 | `query-attributes` | `[PROTOCOL Capabilities]` | not yet |
| P-CAP-10 | `connection-attributes` | `[PROTOCOL Capabilities]` | not yet |
| P-CAP-11 | `multi-statement` | `[PROTOCOL Capabilities]` | not yet |
| P-CAP-12 | `compression` | `[PROTOCOL Capabilities]` | not yet |
| P-CAP-13 | `commit-position` | `[PROTOCOL Capabilities]` | not yet |
| P-CAP-14 | `copy` | `[PROTOCOL Capabilities]` | not yet |
| P-CAP-15 | `row-counts` | `[PROTOCOL Capabilities]` | not yet |
| P-CAP-16 | `generated-values` | `[PROTOCOL Capabilities]` | not yet |
| P-CAP-17 | `fetch-ends` | `[PROTOCOL Capabilities]` | not yet |
| P-CAP-18 | `conditions` | `[PROTOCOL Capabilities]` | not yet |
| P-CAP-19 | No request or tail field of a capability not granted is sent | `[PROTOCOL Capabilities]` | not yet |

### Requests

| ID | Row | Citation | Status |
|---|---|---|---|
| P-REQ-1 | A request sent before the last one is answered, the replies read in turn, in order | `[PROTOCOL Requests]` | not yet |
| P-REQ-2 | Every request but Hello, Answer and Cancel sent only after Ready | `[PROTOCOL Requests]` | not yet |

### Hello 'H'

| ID | Row | Citation | Status |
|---|---|---|---|
| P-HELLO-1 | Hello: version 1, user, mechanism, initial bytes, capabilities, tail 1 attributes | `[PROTOCOL Hello 'H']` | not yet |
| P-HELLO-2 | Connection attributes in Hello, which every server reads, granted or not | `[PROTOCOL Hello 'H']` | not yet |

### Answer 'A'

| ID | Row | Citation | Status |
|---|---|---|---|
| P-ANSWER-1 | Answer: bytes, the client's answer to a Challenge | `[PROTOCOL Answer 'A']` | not yet |

### Query 'Q'

| ID | Row | Citation | Status |
|---|---|---|---|
| P-QUERY-1 | Query: sql, ends flag, tail 1 attributes, 2 multi | `[PROTOCOL Query 'Q']` | not yet |
| P-QUERY-2 | A query answered by Description, Rows and Complete; another statement by Complete; a failure by Error | `[PROTOCOL Query 'Q']` | not yet |
| P-QUERY-3 | A query that returns no row completes with SQLCODE 100, SQLSTATE 02000 | `[PROTOCOL Query 'Q']` | not yet |
| P-QUERY-4 | `ends`: committed as the statement succeeds, rolled back as it fails, the reply saying no transaction is active; a failing commit's Error in place of the Complete | `[PROTOCOL Query 'Q']` | not yet |
| P-QUERY-5 | A result that sent a locator keeps its transaction | `[PROTOCOL Query 'Q']` | not yet |
| P-QUERY-6 | With tag 2, several statements run one by one, `ends` applying to each, tag 5 on each Complete but the last, the first failure's Error ending the replies; text of no statement, one Complete | `[PROTOCOL Query 'Q']` | not yet |

### Prepare 'P'

| ID | Row | Citation | Status |
|---|---|---|---|
| P-PREP-1 | Prepare: the client's number, sql; answered by Prepared or Error, replacing one of that number | `[PROTOCOL Prepare 'P']` | not yet |
| P-PREP-2 | A statement whose cursor is open not replaced (SQLSTATE 24000) | `[PROTOCOL Prepare 'P']` | not yet |

### Execute 'E'

| ID | Row | Citation | Status |
|---|---|---|---|
| P-EXEC-1 | Execute: statement, values, rows (0 for all), ends flag, tail 1 attributes, 3 cursor | `[PROTOCOL Execute 'E']` | not yet |
| P-EXEC-2 | A query's rows in Rows with no Description, then Suspended if the cursor has more, else Complete, the cursor closed | `[PROTOCOL Execute 'E']` | not yet |
| P-EXEC-3 | `ends` as a Query's; a cursor left open keeps the transaction, ended with it under `fetch-ends` | `[PROTOCOL Execute 'E']` | not yet |
| P-EXEC-4 | Cursor 0 unless tag 3 names another, with `cursors`; one already open fails (SQLSTATE 24000) | `[PROTOCOL Execute 'E']` | not yet |

### Fetch 'F'

| ID | Row | Citation | Status |
|---|---|---|---|
| P-FETCH-1 | Fetch: statement, rows, tail 3 cursor; Suspended if more, else Complete | `[PROTOCOL Fetch 'F']` | not yet |
| P-FETCH-2 | A cursor not open fails (SQLSTATE 24000) | `[PROTOCOL Fetch 'F']` | not yet |

### Close 'C'

| ID | Row | Citation | Status |
|---|---|---|---|
| P-CLOSE-1 | Close: statement, tail 3 cursor; answered by Complete, or Error if not open | `[PROTOCOL Close 'C']` | not yet |

### Deallocate 'D'

| ID | Row | Citation | Status |
|---|---|---|---|
| P-DEALLOC-1 | Deallocate: statement; answered by Complete; none such (SQLSTATE 26000), or a cursor of it open (24000), fails | `[PROTOCOL Deallocate 'D']` | not yet |

### Lob 'L', the request

| ID | Row | Citation | Status |
|---|---|---|---|
| P-LOB-1 | 0 read: locator, from, count, characters flag; answered by a Lob reply of data | `[PROTOCOL Lob 'L']` | not yet |
| P-LOB-2 | 1 create: kind; answered by a Lob reply of a locator | `[PROTOCOL Lob 'L']` | not yet |
| P-LOB-3 | 2 append: locator, bytes, a character free to split between appends; answered by Complete | `[PROTOCOL Lob 'L']` | not yet |
| P-LOB-4 | 3 free: locator; answered by Complete | `[PROTOCOL Lob 'L']` | not yet |
| P-LOB-5 | 4 hold: locator, kept past its transaction's commit; answered by Complete | `[PROTOCOL Lob 'L']` | not yet |

### Cancel 'Z'

| ID | Row | Citation | Status |
|---|---|---|---|
| P-CANCEL-1 | Cancel: the key Ready gave, the first and only message of a connection of its own, closed with no reply | `[PROTOCOL Cancel 'Z']` | not yet |
| P-CANCEL-2 | The statement cancelled fails with SQLCODE -920, SQLSTATE TB920 | `[PROTOCOL Cancel 'Z']` | not yet |

### Terminate 'X'

| ID | Row | Citation | Status |
|---|---|---|---|
| P-TERM-1 | Terminate: the session ends, its transaction as SESSION.COMMIT_AT_END says; a failing commit's Error before the close | `[PROTOCOL Terminate 'X']` | not yet |

### Describe 'Y'

| ID | Row | Citation | Status |
|---|---|---|---|
| P-DESC-1 | Describe a prepared statement, cursor 0, answered by Prepared | `[PROTOCOL Describe 'Y']` | not yet |
| P-DESC-2 | Describe an open cursor, answered by Description | `[PROTOCOL Describe 'Y']` | not yet |

### Ping 'G'

| ID | Row | Citation | Status |
|---|---|---|---|
| P-PING-1 | Ping, answered by Pong, at any point after Ready, during a copy too | `[PROTOCOL Ping 'G']` | not yet |

### Reset 'W'

| ID | Row | Citation | Status |
|---|---|---|---|
| P-RESET-1 | Reset: the transaction rolled back; prepared statements, cursors, a copy, temporary tables and settings gone; the authentication and cancel key kept | `[PROTOCOL Reset 'W']` | not yet |
| P-RESET-2 | Its replies: Notice 01T01 if a transaction was active, with `notices`; a Status of each setting, with `status`; a Complete saying no transaction is active | `[PROTOCOL Reset 'W']` | not yet |

### ChangeUser 'U'

| ID | Row | Citation | Status |
|---|---|---|---|
| P-CHUSER-1 | ChangeUser: user, mechanism, initial bytes, then the same Challenge and Answer steps as Hello's | `[PROTOCOL ChangeUser 'U']` | not yet |
| P-CHUSER-2 | Accepted: the session renewed as by Reset, under a new cancel key; the Notice and Statuses, then Ready with the same capabilities | `[PROTOCOL ChangeUser 'U']` | not yet |
| P-CHUSER-3 | Refused: the connection fails | `[PROTOCOL ChangeUser 'U']` | not yet |

### CopyIn 'I'

| ID | Row | Citation | Status |
|---|---|---|---|
| P-COPYIN-1 | CopyIn: table, columns (none for every column), ends flag; no reply | `[PROTOCOL CopyIn 'I']` | not yet |
| P-COPYIN-2 | Until CopyEnd, only CopyData, CopyEnd and Ping sent | `[PROTOCOL CopyIn 'I']` | not yet |

### CopyData 'J'

| ID | Row | Citation | Status |
|---|---|---|---|
| P-COPYDATA-1 | CopyData: a list of rows, as many at a time as the client likes; no reply | `[PROTOCOL CopyData 'J']` | not yet |

### CopyEnd 'N'

| ID | Row | Citation | Status |
|---|---|---|---|
| P-COPYEND-1 | CopyEnd: abandon flag; answered by a Complete whose tag 6 counts the rows inserted, whatever was granted, or by the copy's Error | `[PROTOCOL CopyEnd 'N']` | not yet |
| P-COPYEND-2 | All or nothing: a failure kept until CopyEnd, its detail naming the row, as `row 7 of the copy` | `[PROTOCOL CopyEnd 'N']` | not yet |
| P-COPYEND-3 | `abandon` 1 undoes every row, the Complete counting none | `[PROTOCOL CopyEnd 'N']` | not yet |
| P-COPYEND-4 | A copy whose `ends` is 1 committed as it succeeds, rolled back otherwise; another run under a savepoint of its own | `[PROTOCOL CopyEnd 'N']` | not yet |

### Challenge 'C'

| ID | Row | Citation | Status |
|---|---|---|---|
| P-CHAL-1 | Challenge: bytes, the next step of an exchange | `[PROTOCOL Challenge 'C']` | not yet |

### Ready 'R'

| ID | Row | Citation | Status |
|---|---|---|---|
| P-READY-1 | Ready: authorization, key (16 bytes), capabilities, server | `[PROTOCOL Ready 'R']` | not yet |
| P-READY-2 | The cancel key kept as the client's secret | `[PROTOCOL Ready 'R']` | not yet |

### Prepared 'P'

| ID | Row | Citation | Status |
|---|---|---|---|
| P-PREPD-1 | Prepared: statement, parameters in the order of their `?` marks, columns (none of a statement not a query) | `[PROTOCOL Prepared 'P']` | not yet |

### Description 'D'

| ID | Row | Citation | Status |
|---|---|---|---|
| P-DESCR-1 | Description: columns, of a Query's rows or an open cursor | `[PROTOCOL Description 'D']` | not yet |

### Rows 'B'

| ID | Row | Citation | Status |
|---|---|---|---|
| P-ROWS-1 | Rows: a batch of rows, read as it comes | `[PROTOCOL Rows 'B']` | not yet |

### Suspended 'S'

| ID | Row | Citation | Status |
|---|---|---|---|
| P-SUSP-1 | Suspended: the rows asked for sent, the cursor having more | `[PROTOCOL Suspended 'S']` | not yet |

### Complete 'K'

| ID | Row | Citation | Status |
|---|---|---|---|
| P-COMPL-1 | Complete: SQLCODE 0 or 100, SQLSTATE, active flag, tail 4, 5, 6, 16, 17, 18 | `[PROTOCOL Complete 'K']` | not yet |
| P-COMPL-2 | Tag 4, the log position of the commit the statement made | `[PROTOCOL Complete 'K']` | not yet |
| P-COMPL-3 | Tag 6, the rows a statement changed, or a query's rows in all at its end | `[PROTOCOL Complete 'K']` | not yet |
| P-COMPL-4 | Tag 16, each identity value an INSERT generated, as SQL writes it, in the order of its rows | `[PROTOCOL Complete 'K']` | not yet |
| P-COMPL-5 | Tag 17, each condition the statement raised, a failure as bytes, its own tail ending where its length does | `[PROTOCOL Complete 'K']` | not yet |
| P-COMPL-6 | Tag 18, with `row-counts`, the server's time in microseconds: total, queued, locks | `[PROTOCOL Complete 'K']` | not yet |

### Error 'E'

| ID | Row | Citation | Status |
|---|---|---|---|
| P-ERROR-1 | Error: a failure, its tail 7 to 15 only with `diagnostics` | `[PROTOCOL Error 'E']` | not yet |
| P-ERROR-2 | An Error of class 08 but 08003, or of class 28 as the connection is made, ends the connection | `[PROTOCOL Error 'E']` | not yet |

### Lob 'L', the reply

| ID | Row | Citation | Status |
|---|---|---|---|
| P-LOBR-1 | 0 data: bytes | `[PROTOCOL Lob 'L']` | not yet |
| P-LOBR-2 | 1 locator: `u32` | `[PROTOCOL Lob 'L']` | not yet |

### Notice 'N'

| ID | Row | Citation | Status |
|---|---|---|---|
| P-NOTICE-1 | Notice: SQLSTATE, message, tail 7 to 15 with `diagnostics`, before the statement's completion | `[PROTOCOL Notice 'N']` | not yet |

### Status 'T'

| ID | Row | Citation | Status |
|---|---|---|---|
| P-STATUS-1 | Status: name, value as SQL writes it, empty for a null | `[PROTOCOL Status 'T']` | not yet |
| P-STATUS-2 | One of each at login and after Reset or ChangeUser; after a statement, one of each it changed; a setting reset told at the database's value | `[PROTOCOL Status 'T']` | not yet |
| P-STATUS-3 | AUTHORIZATION | `[PROTOCOL Status 'T']` | not yet |
| P-STATUS-4 | SCHEMA | `[PROTOCOL Status 'T']` | not yet |
| P-STATUS-5 | READ_ONLY, YES or NO | `[PROTOCOL Status 'T']` | not yet |
| P-STATUS-6 | SERVER_VERSION | `[PROTOCOL Status 'T']` | not yet |
| P-STATUS-7 | SERVER_READ_ONLY, YES or NO (gap G2) | `[PROTOCOL Status 'T']` | not yet |
| P-STATUS-8 | CATALOG (gap G2) | `[PROTOCOL Status 'T']` | not yet |
| P-STATUS-9 | OWNER, YES or NO (gap G2) | `[PROTOCOL Status 'T']` | not yet |
| P-STATUS-10 | Every setting a session may set for itself, SESSION.TIME_ZONE and TRANSACTION.ISOLATION among them | `[PROTOCOL Status 'T']` | not yet |

### Pong 'G'

| ID | Row | Citation | Status |
|---|---|---|---|
| P-PONG-1 | Pong, the answer to Ping | `[PROTOCOL Pong 'G']` | not yet |

### Conversations

| ID | Row | Citation | Status |
|---|---|---|---|
| P-CONV-1 | A statement's replies in their order: Rows, then Notices, then Statuses, then Complete, Error or Suspended | `[PROTOCOL Conversations]` | not yet |
| P-CONV-2 | A statement under autocommit, one Query with `ends` set | `[PROTOCOL Conversations]` | not yet |
| P-CONV-3 | A cursor read in parts, its transaction ended by the Fetch with `fetch-ends` | `[PROTOCOL Conversations]` | not yet |
| P-CONV-4 | A copy | `[PROTOCOL Conversations]` | not yet |
| P-CONV-5 | A copy whose row breaks a constraint | `[PROTOCOL Conversations]` | not yet |
| P-CONV-6 | A reset of a session in a transaction | `[PROTOCOL Conversations]` | not yet |

### Errors and notices

| ID | Row | Citation | Status |
|---|---|---|---|
| P-ERRN-1 | Severity ERROR, FATAL, WARNING or NOTICE | `[PROTOCOL Errors and notices]` | not yet |
| P-ERRN-2 | A statement's conditions told one way: in Complete with `conditions`, else as Notices with `notices`, else not at all; a failing statement's as Notices | `[PROTOCOL Errors and notices]` | not yet |
| P-ERRN-3 | The server's own notices always as a Notice | `[PROTOCOL Errors and notices]` | not yet |
| P-ERRN-4 | SQLSTATE 01T01, Reset or ChangeUser rolled back the transaction, a Notice of severity NOTICE | `[PROTOCOL Errors and notices]` | not yet |
| P-ERRN-5 | SQLSTATE TBR01, SQLCODE -920, a replica that had not applied REPLICATION.READ_AFTER's position in time | `[PROTOCOL Errors and notices]` | not yet |
| P-ERRN-6 | A malformed message, a request not granted, a frame too long or a request out of turn fails the connection (SQLCODE -919, SQLSTATE 08006) | `[PROTOCOL Errors and notices]` | not yet |

### A worked example

| ID | Row | Citation | Status |
|---|---|---|---|
| P-EXAMPLE-1 | The Hello of `trust` as ANN asking for `ping`, 41 bytes | `[PROTOCOL A worked example]` | not yet |
| P-EXAMPLE-2 | Ping and Pong, a header alone each | `[PROTOCOL A worked example]` | not yet |
| P-EXAMPLE-3 | The Query of `VALUES 1` with `ends` set | `[PROTOCOL A worked example]` | not yet |
| P-EXAMPLE-4 | The Rows reply of the exact number 1 | `[PROTOCOL A worked example]` | not yet |
| P-EXAMPLE-5 | The Complete with an empty tail, and with `row-counts` its tags 6 and 18 | `[PROTOCOL A worked example]` | not yet |

---

## The client library

From `doc/client/02-library.md`, The Client Library.

### Connecting

| ID | Row | Citation | Status |
|---|---|---|---|
| C-CONN-1 | Connect over TCP | `[CLIENT Connecting]` | not yet |
| C-CONN-2 | Connect over a Unix socket, or on Windows the named pipe `\\.\pipe\turborel` | `[CLIENT Connecting]` | not yet |
| C-CONN-3 | Connect to a target, TCP or local, over TLS or not | `[CLIENT Connecting]` | not yet |
| C-CONN-4 | SCRAM-SHA-256 of a password, refused (SQLSTATE 08006) unless the server proves it knows the user's verifier | `[CLIENT Connecting]` | not yet |
| C-CONN-5 | SCRAM only over TLS, a Unix socket or a named pipe, unless the program asks for it in the clear | `[CLIENT Connecting]` | not yet |
| C-CONN-6 | SCRAM-SHA-256-PLUS over TLS: by `tls-exporter` over TLS 1.3, by the server's certificate over TLS 1.2 | `[CLIENT Connecting]` | not yet |
| C-CONN-7 | A TLS stream the program opened, bound before SCRAM-SHA-256-PLUS | `[CLIENT Connecting]` | not yet |
| C-CONN-8 | `password`, sent whole, only over TLS, a Unix socket or a named pipe | `[CLIENT Connecting]` | not yet |
| C-CONN-9 | `certificate`: TLS trusting a PEM file of authorities, presenting a certificate chain and key from two more | `[CLIENT Connecting]` | not yet |
| C-CONN-10 | `trust` | `[CLIENT Connecting]` | not yet |
| C-CONN-11 | A password, or SCRAM, refused over plain TCP before connecting (SQLSTATE 28000) | `[CLIENT Connecting]` | not yet |
| C-CONN-12 | TLS trusting a file's authorities, the platform's, or both; SSL_CERT_FILE and SSL_CERT_DIR | `[CLIENT Connecting]` | not yet |
| C-CONN-13 | The server's product and the session's authorization identifier, as Ready told them | `[CLIENT Connecting]` | not yet |
| C-CONN-14 | Terminate: the transaction as SESSION.COMMIT_AT_END says, a failing commit's failure given, waiting at most the read timeout, else 60 seconds | `[CLIENT Connecting]` | not yet |

### Timeouts

| ID | Row | Citation | Status |
|---|---|---|---|
| C-TIME-1 | The connect timeout, for connecting, TLS and each step of the login: 30 seconds by default | `[CLIENT Timeouts]` | not yet |
| C-TIME-2 | The read timeout, for each read or write after: none by default | `[CLIENT Timeouts]` | not yet |
| C-TIME-3 | Timeouts of the program's own, and a connection's read timeout changed | `[CLIENT Timeouts]` | not yet |
| C-TIME-4 | A wait that runs out loses the connection (SQLSTATE 08006), saying the server did not answer in time | `[CLIENT Timeouts]` | not yet |
| C-TIME-5 | A named pipe bounded only as it is opened | `[CLIENT Timeouts]` | not yet |
| C-TIME-6 | Replies taken up to 16 MiB, or as many bytes as the program says; a longer one loses the connection | `[CLIENT Timeouts]` | not yet |

### Running statements

| ID | Row | Citation | Status |
|---|---|---|---|
| C-RUN-1 | Run a statement: a query's columns and rows, or another statement's completion, its SQLCODE and SQLSTATE | `[CLIENT Running statements]` | not yet |
| C-RUN-2 | A failure: SQLCODE, SQLSTATE, message, the rule it cites apart, its position | `[CLIENT Running statements]` | not yet |
| C-RUN-3 | A query's rows given a batch at a time, as they come | `[CLIENT Running statements]` | not yet |
| C-RUN-4 | Every value: exact, approximate, character, binary, datetime, interval, a plug-in's, null | `[CLIENT Running statements]` | not yet |
| C-RUN-5 | Whether the session's transaction is active, as the server said after the last statement | `[CLIENT Running statements]` | not yet |
| C-RUN-6 | Cancel from another thread, giving up after 10 seconds, or a limit of the program's | `[CLIENT Running statements]` | not yet |
| C-RUN-7 | A transaction begun by the first statement, lasting until COMMIT or ROLLBACK | `[CLIENT Running statements]` | not yet |
| C-RUN-8 | Autocommit: each statement its own transaction, by `ends`, with no COMMIT sent | `[CLIENT Running statements]` | not yet |

### Prepared statements

| ID | Row | Citation | Status |
|---|---|---|---|
| C-PREP-1 | Prepare, its dynamic parameters written `?` | `[CLIENT Prepared statements]` | not yet |
| C-PREP-2 | Execute with values, as many times as wanted | `[CLIENT Prepared statements]` | not yet |
| C-PREP-3 | The type each parameter takes, and a query's columns | `[CLIENT Prepared statements]` | not yet |
| C-PREP-4 | Open a cursor and take its first rows, fetch the next batch, close it | `[CLIENT Prepared statements]` | not yet |
| C-PREP-5 | Deallocate | `[CLIENT Prepared statements]` | not yet |
| C-PREP-6 | A prepared statement valid across transactions | `[CLIENT Prepared statements]` | not yet |

### Large objects

| ID | Row | Citation | Status |
|---|---|---|---|
| C-LOB-1 | A CLOB or BLOB of at most SERVER.LOB_INLINE_BYTES whole in its row; a longer one as its locator and lengths | `[CLIENT Large objects]` | not yet |
| C-LOB-2 | Read a range, by octets or by a CLOB's characters, at most 256 KiB a chunk | `[CLIENT Large objects]` | not yet |
| C-LOB-3 | A reader of the whole value, a chunk at a time, as the language's stream | `[CLIENT Large objects]` | not yet |
| C-LOB-4 | A locator valid until its transaction ends, the transaction kept open under autocommit too | `[CLIENT Large objects]` | not yet |
| C-LOB-5 | Free a locator | `[CLIENT Large objects]` | not yet |
| C-LOB-6 | Hold a locator past the commit, until it is freed or a rollback ends it | `[CLIENT Large objects]` | not yet |
| C-LOB-7 | Create a value a piece at a time through a writer, and pass it as a parameter | `[CLIENT Large objects]` | not yet |
| C-LOB-8 | A CLOB's octets UTF-8, a character split between writes | `[CLIENT Large objects]` | not yet |
| C-LOB-9 | An import's field longer than 64 KiB for a CLOB or BLOB column sent by creating a large object | `[CLIENT Large objects]` | not yet |

### XML values

| ID | Row | Citation | Status |
|---|---|---|---|
| C-XML-1 | An XML value read as its serialization, its text | `[CLIENT XML values]` | not yet |
| C-XML-2 | Its nodes parsed from it | `[CLIENT XML values]` | not yet |
| C-XML-3 | An XML parameter made of its text | `[CLIENT XML values]` | not yet |
| C-XML-4 | A value the server cannot serialize fails the fetch (SQLSTATE 2200W) | `[CLIENT XML values]` | not yet |

### UUIDs

| ID | Row | Citation | Status |
|---|---|---|---|
| C-UUID-1 | A UUID read, whatever types the program registered: its 16 octets and its text | `[CLIENT UUIDs]` | not yet |
| C-UUID-2 | A UUID parameter made of its octets or of its text | `[CLIENT UUIDs]` | not yet |

### Importing

| ID | Row | Citation | Status |
|---|---|---|---|
| C-IMPORT-1 | Import a source's rows into a table over a connection | `[CLIENT Importing]` | not yet |
| C-IMPORT-2 | A source: its headings, names and types if known, then each record with where it began, held a record at a time | `[CLIENT Importing]` | not yet |
| C-IMPORT-3 | Delimited text, CSV and tab-separated, with a header, a delimiter and a text for null | `[CLIENT Importing]` | not yet |
| C-IMPORT-4 | Rows committed a batch at a time, 1000 by default, or all at once | `[CLIENT Importing]` | not yet |
| C-IMPORT-5 | A failing row skipped and given to the program, if asked | `[CLIENT Importing]` | not yet |
| C-IMPORT-6 | No transaction active on the session | `[CLIENT Importing]` | not yet |
| C-IMPORT-7 | An import's failure: where its record began, why (the input's or SQL's), the rows committed and rolled back | `[CLIENT Importing]` | not yet |

### What a connection asks for

| ID | Row | Citation | Status |
|---|---|---|---|
| C-ASK-1 | Every capability but compression asked for by default | `[CLIENT What a connection asks for]` | not yet |
| C-ASK-2 | An offer of the program's own: none, compression, connection attributes | `[CLIENT What a connection asks for]` | not yet |
| C-ASK-3 | What was granted | `[CLIENT What a connection asks for]` | not yet |
| C-ASK-4 | A method needing a capability not granted fails before it sends anything | `[CLIENT What a connection asks for]` | not yet |

### What the server tells

| ID | Row | Citation | Status |
|---|---|---|---|
| C-TOLD-1 | A session setting as the server last told it, and all of them, with no round trip | `[CLIENT What the server tells]` | not yet |
| C-TOLD-2 | Notices given to a handler as they come; with none, the last 64 kept and taken | `[CLIENT What the server tells]` | not yet |
| C-TOLD-3 | The last statement's conditions, with `conditions` | `[CLIENT What the server tells]` | not yet |
| C-TOLD-4 | The rows a statement changed, or a query returned | `[CLIENT What the server tells]` | not yet |
| C-TOLD-5 | The identity values an INSERT generated, in the order of its rows | `[CLIENT What the server tells]` | not yet |
| C-TOLD-6 | The server's time for the statement: total, queued, locks | `[CLIENT What the server tells]` | not yet |
| C-TOLD-7 | The log position of the last commit | `[CLIENT What the server tells]` | not yet |
| C-TOLD-8 | A failure's diagnostics: severity, detail, hint, context, schema, table, column, data type, constraint | `[CLIENT What the server tells]` | not yet |
| C-TOLD-9 | Under autocommit with `fetch-ends`, a cursor's transaction ended as it ends: the last row's fetch commits, a failing fetch rolls back, close commits | `[CLIENT What the server tells]` | not yet |

### Controlling the session

| ID | Row | Citation | Status |
|---|---|---|---|
| C-CTRL-1 | Ping | `[CLIENT Controlling the session]` | not yet |
| C-CTRL-2 | Reset | `[CLIENT Controlling the session]` | not yet |
| C-CTRL-3 | Change user | `[CLIENT Controlling the session]` | not yet |
| C-CTRL-4 | A transaction either rolls back told by notice 01T01 | `[CLIENT Controlling the session]` | not yet |
| C-CTRL-5 | Query attributes carried by every later statement, until set again | `[CLIENT Controlling the session]` | not yet |
| C-CTRL-6 | Several statements as one request: each outcome, and the failure that stopped the rest | `[CLIENT Controlling the session]` | not yet |
| C-CTRL-7 | Describe a prepared statement again | `[CLIENT Controlling the session]` | not yet |
| C-CTRL-8 | Several numbered cursors of one statement open at once | `[CLIENT Controlling the session]` | not yet |
| C-CTRL-9 | Describe an open cursor's columns | `[CLIENT Controlling the session]` | not yet |

### Copying and exporting

| ID | Row | Citation | Status |
|---|---|---|---|
| C-COPY-1 | Copy into a table, of the columns named or all | `[CLIENT Copying and exporting]` | not yet |
| C-COPY-2 | Send rows, many to a message, with no reply each | `[CLIENT Copying and exporting]` | not yet |
| C-COPY-3 | Finish, giving the rows inserted | `[CLIENT Copying and exporting]` | not yet |
| C-COPY-4 | All or nothing: a row refused undoes every row, its failure's detail naming the row | `[CLIENT Copying and exporting]` | not yet |
| C-COPY-5 | A copy dropped before it finishes abandoned | `[CLIENT Copying and exporting]` | not yet |
| C-COPY-6 | Copy the rows an iterator gives | `[CLIENT Copying and exporting]` | not yet |
| C-COPY-7 | Importing by copy where the server grants it and no column is a large object | `[CLIENT Copying and exporting]` | not yet |
| C-COPY-8 | Export as CSV, a header of the columns' names then a record for each row, as they come | `[CLIENT Copying and exporting]` | not yet |
| C-COPY-9 | Export as the protocol's own frames, read back with every value as it was | `[CLIENT Copying and exporting]` | not yet |

### The SQL-agent

| ID | Row | Citation | Status |
|---|---|---|---|
| C-AGENT-1 | A program's connections, each named, one current | `[CLIENT The SQL-agent]` | not yet |
| C-AGENT-2 | CONNECT, through a connector the program gives, to the address and as the user it names | `[CLIENT The SQL-agent]` | not yet |
| C-AGENT-3 | SET CONNECTION | `[CLIENT The SQL-agent]` | not yet |
| C-AGENT-4 | DISCONNECT | `[CLIENT The SQL-agent]` | not yet |
| C-AGENT-5 | Every other statement sent to the current connection | `[CLIENT The SQL-agent]` | not yet |

---

## Settings, pipelines and pools

From `doc/client/02-library-connections.md`, Settings, Pipelines and Pools.

### Connecting by settings

| ID | Row | Citation | Status |
|---|---|---|---|
| C-SET-1 | Connect as settings say, giving a connection like a target's | `[CLIENT Connecting by settings]` | not yet |
| C-SET-2 | A password proved by SCRAM-SHA-256, else sent by `password`; with none, the certificate named, else trust | `[CLIENT Connecting by settings]` | not yet |
| C-SET-3 | A secret mechanism refused over plain TCP before anything is sent (SQLSTATE 28000) | `[CLIENT Connecting by settings]` | not yet |

### Where settings come from

| ID | Row | Citation | Status |
|---|---|---|---|
| C-OPT-1 | `host`: the servers, comma-separated, each with its port, an IPv6 address in brackets, a path a Unix socket or named pipe; `localhost` | `[CLIENT Where settings come from]` | not yet |
| C-OPT-2 | `port`: one for all, or one each; 7422 | `[CLIENT Where settings come from]` | not yet |
| C-OPT-3 | `user`: none: it must be given | `[CLIENT Where settings come from]` | not yet |
| C-OPT-4 | `password`: the password file's | `[CLIENT Where settings come from]` | not yet |
| C-OPT-5 | `tls_mode`: `prefer` | `[CLIENT Where settings come from]` | not yet |
| C-OPT-6 | `channel_binding`: `prefer` | `[CLIENT Where settings come from]` | not yet |
| C-OPT-7 | `application_name`: sent as the connection attribute `application`; none | `[CLIENT Where settings come from]` | not yet |
| C-OPT-8 | `connect_timeout`: whole seconds, 0 for no limit; 30 | `[CLIENT Where settings come from]` | not yet |
| C-OPT-9 | `service`: none | `[CLIENT Where settings come from]` | not yet |
| C-OPT-10 | `service_file`: `~/.turborel_service.conf` | `[CLIENT Where settings come from]` | not yet |
| C-OPT-11 | `passfile`: `~/.turborel_pass` | `[CLIENT Where settings come from]` | not yet |
| C-OPT-12 | `target`: `any`, `read-write` or `read-only`; `any` | `[CLIENT Where settings come from]` | not yet |
| C-OPT-13 | `load_balance`: `disable` or `random`; `disable` | `[CLIENT Where settings come from]` | not yet |
| C-OPT-14 | `tls_roots`: none | `[CLIENT Where settings come from]` | not yet |
| C-OPT-15 | `tls_system_roots`: `false` | `[CLIENT Where settings come from]` | not yet |
| C-OPT-16 | `tls_certificate` and `tls_key`: none | `[CLIENT Where settings come from]` | not yet |
| C-OPT-17 | `server_name`: the host's | `[CLIENT Where settings come from]` | not yet |
| C-OPT-18 | Layers: the program's options or URI, then the service file's section, then the environment, then the defaults | `[CLIENT Where settings come from]` | not yet |
| C-OPT-19 | TURBOREL_HOST, _PORT, _USER, _PASSWORD, _TLS_MODE, _APPLICATION_NAME, _CONNECT_TIMEOUT, _SERVICE, _SERVICE_FILE and _PASSFILE; one set but empty gives nothing | `[CLIENT Where settings come from]` | not yet |
| C-OPT-20 | The environment read through a function the program gives | `[CLIENT Where settings come from]` | not yet |
| C-OPT-21 | A setting that cannot be read, a service file unread or without the section, or no user, refused (SQLSTATE 08001) | `[CLIENT Where settings come from]` | not yet |

### The connection URI

| ID | Row | Citation | Status |
|---|---|---|---|
| C-URI-1 | `turborel://` with user, password, hosts and ports, and settings | `[CLIENT The connection URI]` | not yet |
| C-URI-2 | Its parts percent-encoded; an IPv6 address in brackets; a Unix socket's path | `[CLIENT The connection URI]` | not yet |
| C-URI-3 | Another scheme, a path, a setting not in the table or a pair without `=` refused (SQLSTATE 08001) | `[CLIENT The connection URI]` | not yet |

### The service file

| ID | Row | Citation | Status |
|---|---|---|---|
| C-SVC-1 | Sections `[name]`, lines `setting = value`, `#` comments and blank lines skipped | `[CLIENT The service file]` | not yet |
| C-SVC-2 | A section cannot set `service` or `service_file` | `[CLIENT The service file]` | not yet |
| C-SVC-3 | A malformed line refused, its file and line named | `[CLIENT The service file]` | not yet |

### The password file

| ID | Row | Citation | Status |
|---|---|---|---|
| C-PASS-1 | Lines `host:port:user:password`; `*` matching anything; `\` escaping; `#` comments | `[CLIENT The password file]` | not yet |
| C-PASS-2 | Looked up by the server and user of each connection, the first line that matches taken; a Unix socket matched by its path and the default port | `[CLIENT The password file]` | not yet |
| C-PASS-3 | Read only if a regular file, or a link to one | `[CLIENT The password file]` | not yet |

### Several servers

| ID | Row | Citation | Status |
|---|---|---|---|
| C-HOSTS-1 | Hosts tried in the order given, or in a random order for each connection with `load_balance=random` | `[CLIENT Several servers]` | not yet |
| C-HOSTS-2 | Each address a name resolves to tried, each step within the connect timeout | `[CLIENT Several servers]` | not yet |
| C-HOSTS-3 | A server unreachable, refusing the user, or not of the role asked passed for the next | `[CLIENT Several servers]` | not yet |
| C-HOSTS-4 | With none kept, a failure naming each address and why (SQLSTATE 08001; 28000 if the last refused the user) | `[CLIENT Several servers]` | not yet |
| C-HOSTS-5 | `target=read-write`, a server alone or its group's primary | `[CLIENT Several servers]` | not yet |
| C-HOSTS-6 | `target=read-only`, a replica that follows its group | `[CLIENT Several servers]` | not yet |
| C-HOSTS-7 | The role told by SERVER_READ_ONLY; of a server that does not tell it, read from INFORMATION_SCHEMA.REPLICAS | `[CLIENT Several servers]` | not yet |
| C-HOSTS-8 | The role a connection's session sees | `[CLIENT Several servers]` | not yet |

### TLS by mode

| ID | Row | Citation | Status |
|---|---|---|---|
| C-TLS-1 | `disable` | `[CLIENT TLS by mode]` | not yet |
| C-TLS-2 | `prefer`: TLS if the server takes it, else plain TCP, connecting again after a failed handshake | `[CLIENT TLS by mode]` | not yet |
| C-TLS-3 | `require` | `[CLIENT TLS by mode]` | not yet |
| C-TLS-4 | `verify-ca`, needing the authorities trusted | `[CLIENT TLS by mode]` | not yet |
| C-TLS-5 | `verify-full`, against `server_name`, else the host's | `[CLIENT TLS by mode]` | not yet |
| C-TLS-6 | No TLS over a Unix socket or a named pipe | `[CLIENT TLS by mode]` | not yet |
| C-TLS-7 | `channel_binding` `disable` and `prefer` | `[CLIENT TLS by mode]` | not yet |
| C-TLS-8 | `channel_binding` `require`, refusing before any connection settings that cannot bind (SQLSTATE 28000) | `[CLIENT TLS by mode]` | not yet |

### Pipelines

| ID | Row | Citation | Status |
|---|---|---|---|
| C-PIPE-1 | Queue queries and executions, run them, one outcome each, in order | `[CLIENT Pipelines]` | not yet |
| C-PIPE-2 | A failure its request's own, the requests after it run | `[CLIENT Pipelines]` | not yet |
| C-PIPE-3 | Requests written a window of 64 KiB at a time, its replies read before the next | `[CLIENT Pipelines]` | not yet |
| C-PIPE-4 | Under autocommit, each request its own transaction | `[CLIENT Pipelines]` | not yet |
| C-PIPE-5 | Skip on error: a savepoint before each request but the first, those after a failure rolled back and skipped, those not yet written never sent | `[CLIENT Pipelines]` | not yet |
| C-PIPE-6 | A skipping batch one transaction, committed as it ends under autocommit where it began none | `[CLIENT Pipelines]` | not yet |
| C-PIPE-7 | Run fails if the connection is lost (SQLSTATE 08006) or a skipping batch cannot be undone | `[CLIENT Pipelines]` | not yet |

### Pools

| ID | Row | Citation | Status |
|---|---|---|---|
| C-POOL-1 | A bounded set of connections the program's threads share, its clones the same pool | `[CLIENT Pools]` | not yet |
| C-POOL-2 | Get an idle connection that answers, or make one while fewer than `max` are made, or wait | `[CLIENT Pools]` | not yet |
| C-POOL-3 | A pooled connection given back as it is released | `[CLIENT Pools]` | not yet |
| C-POOL-4 | `max`, 10 by default | `[CLIENT Pools]` | not yet |
| C-POOL-5 | `max_idle`, 10 by default | `[CLIENT Pools]` | not yet |
| C-POOL-6 | `idle_timeout`, 10 minutes by default | `[CLIENT Pools]` | not yet |
| C-POOL-7 | `max_lifetime`, 1 hour by default | `[CLIENT Pools]` | not yet |
| C-POOL-8 | `wait`, 30 seconds by default | `[CLIENT Pools]` | not yet |
| C-POOL-9 | `check`, yes by default | `[CLIENT Pools]` | not yet |
| C-POOL-10 | `reset`, none by default | `[CLIENT Pools]` | not yet |
| C-POOL-11 | Given back reset by the protocol's Reset, autocommit off, then the `reset` statements | `[CLIENT Pools]` | not yet |
| C-POOL-12 | Checked by Ping | `[CLIENT Pools]` | not yet |
| C-POOL-13 | Of a server that takes neither, the check ROLLBACK and the reset one pipeline | `[CLIENT Pools]` | not yet |
| C-POOL-14 | A connection lost, failing its reset, past its lifetime or beyond `max_idle` closed | `[CLIENT Pools]` | not yet |
| C-POOL-15 | One idle past `idle_timeout`, or failing its check, closed as get meets it | `[CLIENT Pools]` | not yet |
| C-POOL-16 | Get fails with SQLSTATE 08001 if none comes back within `wait`, or with the failure of making one | `[CLIENT Pools]` | not yet |
| C-POOL-17 | A pool made of settings, or of anything that makes a connection | `[CLIENT Pools]` | not yet |
| C-POOL-18 | No thread started by the pool; each wait the waiter's own | `[CLIENT Pools]` | not yet |

### The SCRAM key cache

| ID | Row | Citation | Status |
|---|---|---|---|
| C-KEY-1 | The keys a password derived kept after a login the server proved, a later login of the same salt and iterations skipping the derivation | `[CLIENT The SCRAM key cache]` | not yet |
| C-KEY-2 | One cache for every connection the same settings make | `[CLIENT The SCRAM key cache]` | not yet |
| C-KEY-3 | A cache given to a mechanism the program makes | `[CLIENT The SCRAM key cache]` | not yet |
| C-KEY-4 | Its hits and misses | `[CLIENT The SCRAM key cache]` | not yet |
| C-KEY-5 | An entry found by the salt, the iterations and a tag of the password under a random secret of the cache's own | `[CLIENT The SCRAM key cache]` | not yet |
| C-KEY-6 | At most 64 entries, the oldest dropped first | `[CLIENT The SCRAM key cache]` | not yet |
| C-KEY-7 | An entry dropped when a login that used it fails | `[CLIENT The SCRAM key cache]` | not yet |
| C-KEY-8 | Held in the process's memory alone | `[CLIENT The SCRAM key cache]` | not yet |

---

## The standard API

This driver's own rows, over the rows above (RULES.md D2). Their IDs are
`S-API-1` and on; they cite the driver's decision, `[DESIGN] D2`, or a
later decision of RULES.md.

| ID | Row | Citation | Status |
|---|---|---|---|
| S-API-1 | `Turborel.connect`, by a `turborel://` URI or settings, giving a `Turborel::Connection` | `[DESIGN] D2` | not yet |
| S-API-2 | `exec`, a statement's text, and `exec_params`, with `?` parameters | `[DESIGN] D2` | not yet |
| S-API-3 | `prepare` and `exec_prepared` | `[DESIGN] D2` | not yet |
| S-API-4 | `Turborel::Result`: its columns, its rows by row and by column, each value as Appendix A maps it, and its completion | `[DESIGN] D2` | not yet |
| S-API-5 | Transactions: `transaction` with a block, committed as it ends and rolled back as it raises | `[DESIGN] D2` | not yet |
| S-API-6 | Every failure of the plain API a `Turborel::Error`, carrying the server's failure | `[DESIGN] D2` | not yet |
| S-API-7 | The ActiveRecord adapter for Rails 8.1 and later, registered as `turborel` | `[DESIGN] D2` | not yet |
