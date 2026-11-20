# Large Objects

[Contents](README.md)

## NAME

`Turborel::Client::Connection`: large objects read by range or as a
stream, written a piece at a time, freed and held.

## SYNOPSIS

```ruby
connection.read_lob(lob, from, count, characters: false) # => String, binary
connection.lob_reader(lob)                               # => LobReader
connection.create_lob(kind)                              # => LobWriter, of :character or :binary
connection.free_lob(lob)                                 # => Completion
connection.hold_lob(lob)                                 # => Completion

reader.read(length = nil, buffer = nil)   reader.readpartial(length, buffer = nil)   reader.eof?
writer.write(*pieces)   writer << piece   writer.flush   writer.finish   # => Lob
```

## DESCRIPTION

A CLOB or BLOB of at most SERVER.LOB_INLINE_BYTES, 64 KiB by default,
comes in its row whole, a `Turborel::Lob` whose `data` holds it; a
longer one as a `Turborel::Lob` of its `locator`, `octets` and
`characters`. A locator is valid until the transaction that read it
ends, and a result that sent one keeps its transaction active, under
autocommit too.

`read_lob` gives at most `count` octets from octet `from`, or of a
CLOB's characters if `characters`, at most a chunk of 256 KiB; fewer
only at the value's end or a chunk's. Of a value held whole it reads with
no round trip. `lob_reader` reads the whole value a chunk at a time, as
an IO's `read` and `readpartial`. `create_lob` gives a writer whose
pieces are sent in Appends of at most a chunk, a CLOB's cut where a
character ends, so a character may be split between writes; `finish`
gives the value to pass as a parameter, by its locator, used once.
`free_lob` ends a locator; `hold_lob` keeps it past the commit, until it
is freed or a rollback ends it.

## ERRORS

| SQLSTATE | SQLCODE | When |
|---|---|---|
| 0F001 | -301 | A locator no longer valid |
| 22000 | -301 | `free_lob` or `hold_lob` of a value held whole, or `read_lob` of one neither held nor located |
| 22021 | -301 | A CLOB written whose octets are not UTF-8 |
| 22001 | -301 | A value longer than its column |
| TB910 | -910 | A kind other than `:character` and `:binary` |
| 08006 | -919 | The server sending less of a value than its length, or a reply out of turn |

## EXAMPLES

```ruby
conn = Turborel::Client.connect("127.0.0.1", 7422, user: "ann", mechanism: Turborel::Client::Trust.new)
conn.query("CREATE TABLE NOTES2 (N CLOB(1M))")
writer = conn.create_lob(:character)
writer << "é" * 40_000 << "x"
conn.execute(conn.prepare("INSERT INTO NOTES2 VALUES (?)"), [writer.finish])
note = conn.query("SELECT N FROM NOTES2").rows.first.first
p [note.octets, note.characters]
p conn.read_lob(note, 39_998, 3, characters: true).force_encoding("UTF-8")
conn.query("ROLLBACK")
conn.terminate
```

```text
[80001, 40001]
"ééx"
```

## STANDARD

[PROTOCOL Lob 'L'] and [PROTOCOL Values] of [The Native
Protocol](https://github.com/turborel/turborel/blob/main/doc/client/05-protocol.md);
[CLIENT Large objects] of [The Client
Library](https://github.com/turborel/turborel/blob/main/doc/client/02-library.md).

## SEE ALSO

[Large Objects](../user/06-large-objects.md), [Values](23-values.md),
[Copy, Import and Export](25-copy.md)
