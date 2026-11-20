# TODO

Open work, by milestone. The milestones and their items are the same in
every Turborel driver, and each item names the rows of
[CONFORMANCE.md](CONFORMANCE.md) it marks done. An item covers only the
rows CONFORMANCE.md still marks "not yet"; one whose rows are all done
leaves this file, and git keeps its history. How the driver is built is
in [RULES.md](RULES.md).

Code never cites this file (R-DOC-5).

[M1 Codec](#m1-codec) · [M2 Connect](#m2-connect) ·
[M3 Statements](#m3-statements) ·
[M4 Large objects and bulk](#m4-large-objects-and-bulk) ·
[M5 Settings](#m5-settings) · [M6 Throughput](#m6-throughput) ·
[M7 Standard API](#m7-standard-api) · [M8 Parity audit](#m8-parity-audit)

---

## M1 Codec

Every message encoded and decoded, with no I/O, each with its codec
tests.

- Frames, fields and compression: the P-FRAME, P-ZFRAME and P-FIELD
  rows.
- The data types and values, tested at their edges: the P-TYPE, P-VAL
  and P-JSON rows but P-VAL-102 and P-VAL-103, and the P-COMP rows.
- The tail: the P-TAIL rows.
- The messages whose rows are their fields alone: P-HELLO-1,
  P-ANSWER-1, P-QUERY-1, P-EXEC-1, P-COPYIN-1, P-COPYDATA-1, P-CHAL-1,
  P-READY-1, P-PREPD-1, P-DESCR-1, P-ROWS-1, P-SUSP-1, P-COMPL-1,
  P-ERROR-1, P-NOTICE-1, P-STATUS-1, P-PONG-1, and the P-LOBR rows. The
  other requests' fields are encoded here too, and their rows, which say
  how the server answers, are done in the milestone that names them.
- The worked example, byte for byte, and malformed frames that must fail
  the connection: the P-EXAMPLE rows and P-ERRN-6.
- The manual: Appendix A and the API Reference's page of values.

## M2 Connect

- Transport: P-INTRO-1 to P-INTRO-3, C-CONN-1 to C-CONN-3, and the
  C-TIME rows.
- Logging in: the P-OPEN and P-MECH rows, P-INTRO-4, P-HELLO-2,
  P-READY-2, P-ERROR-2, C-CONN-4, C-CONN-5, C-CONN-8, C-CONN-10,
  C-CONN-11 and C-CONN-13.
- TLS: C-CONN-6, C-CONN-7, C-CONN-9 and C-CONN-12, by the language's
  own TLS.
- Capabilities and status: P-CAP-2, P-CAP-10, P-CAP-12, P-CAP-19,
  P-STATUS-2 to P-STATUS-10, the C-ASK rows and C-TOLD-1.
- The SCRAM key cache: C-KEY-1 and C-KEY-3 to C-KEY-8.
- Ending: P-CANCEL-1, P-CANCEL-2, P-TERM-1, C-CONN-14 and C-RUN-6.
- The live tests' server set-up, with test certificates, SCRAM users and
  SERVER.TRUST_LOCAL, on `ghcr.io/turborel/turborel:nightly` in CI
  (R-TEST-8).
- The manual: the User's Guide's chapter Connecting and the API
  Reference's page of connections.

## M3 Statements

- Queries and prepared statements: P-REQ-2, P-QUERY-2 to P-QUERY-6,
  P-EXEC-2 to P-EXEC-4, the P-PREP, P-FETCH, P-CLOSE, P-DEALLOC and
  P-DESC rows, the C-RUN rows but C-RUN-6, and the C-PREP rows.
- Completions, failures, notices and conditions: P-COMPL-2 to
  P-COMPL-6, the P-ERRN rows but P-ERRN-6, and C-TOLD-2 to C-TOLD-9.
- The session: P-PING-1, the P-RESET and P-CHUSER rows, and the C-CTRL
  rows.
- Capabilities: P-CAP-1, P-CAP-3 to P-CAP-9, P-CAP-11, P-CAP-13 and
  P-CAP-15 to P-CAP-18.
- XML and UUID values: the C-XML and C-UUID rows.
- Conversations: P-CONV-1 to P-CONV-3 and P-CONV-6.
- The manual: the chapters Running Queries, Prepared Statements,
  Transactions and Errors and Diagnostics; the pages of statements and
  errors; Appendix B.

## M4 Large objects and bulk

- Large objects: P-VAL-102, P-VAL-103, the P-LOB rows, and the C-LOB
  rows.
- Copy: P-CAP-14, P-COPYIN-2, the P-COPYEND rows, P-CONV-4, P-CONV-5,
  and the C-COPY rows.
- Import and export: the C-IMPORT rows.
- The manual: the chapters Large Objects and Copying, Importing and
  Exporting; the pages of large objects and copy.

## M5 Settings

- Settings, the URI and the files, read as turborel-client's settings
  tests read them (R-TEST-9): the C-SET, C-OPT, C-URI, C-SVC and C-PASS
  rows.
- Several servers and roles: the C-HOSTS rows.
- TLS modes and channel binding: the C-TLS rows.
- The key cache shared by settings: C-KEY-2.
- The manual: the chapter Settings, the page of settings, and
  Appendix C.

## M6 Throughput

- Pipelines: P-REQ-1 and the C-PIPE rows.
- Pools: the C-POOL rows.
- The SQL-agent: the C-AGENT rows.
- The manual: the chapter Pipelines and Pools; the pages of pipelines,
  pools and the SQL-agent.

## M7 Standard API

- The standard API (RULES.md D2): the S-API rows.
- The manual: the chapter Installing, the API Reference's pages of the
  standard API, and every page the earlier milestones filled checked
  again against the code, every example run.

## M8 Parity audit

- Every row of CONFORMANCE.md checked against turborel-client and the
  spec, the coverage floor held (RULES.md D7), and this file empty.
- Once Turborel keeps a file of sample frames beside the spec, every
  frame of it decoded, at a pinned commit.
