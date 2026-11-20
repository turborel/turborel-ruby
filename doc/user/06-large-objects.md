# Large Objects

[Contents](README.md)

A CLOB or BLOB value of at most SERVER.LOB_INLINE_BYTES, 64 KiB unless
the operator sets otherwise, comes in its row whole: a `Turborel::Lob`
whose `data` holds its text or octets. A longer one comes as a
`Turborel::Lob` that holds its `locator` and its lengths, `octets` and
`characters`, not its octets. This chapter tells how a program reads
one, writes one, and how long a locator lasts.

## Reading

`read_lob(lob, from, count)` reads at most `count` octets from octet
`from`, the first 0, at most a chunk of 256 KiB at a time;
`characters: true` counts a CLOB's characters instead. Of a value held
whole, it reads with no round trip. `lob_reader(lob)` gives a stream of
the whole value, read a chunk at a time: its `read` and `readpartial`
are an IO's, so `IO.copy_stream` copies it.

## Writing

`create_lob(kind)`, of `:character` or `:binary`, gives a writer: each
`write` or `<<` takes a piece, sent in Appends of at most a chunk, and
`finish` gives the value to pass as a parameter of a CLOB or BLOB. A
CLOB's octets must be UTF-8, and a character may be split between
writes.

```ruby
conn = Turborel::Client.connect("127.0.0.1", 7422, user: "ann", mechanism: Turborel::Client::Trust.new)
conn.query("CREATE TABLE SCANS (ID INTEGER, IMAGE BLOB(10M))")
writer = conn.create_lob(:binary)
1024.times { writer.write("\x07".b * 4096) }
insert = conn.prepare("INSERT INTO SCANS VALUES (1, ?)")
conn.execute(insert, [writer.finish])
conn.query("COMMIT")
image = conn.query("SELECT IMAGE FROM SCANS").rows.first.first
p [image.data, image.octets]
p conn.lob_reader(image).read.bytesize
p conn.read_lob(image, 0, 4)
conn.query("COMMIT")
conn.terminate
```

```text
[nil, 4194304]
4194304
"\a\a\a\a"
```

## How long a locator lasts

A locator is valid until the transaction that read it ends. A statement
whose reply sent one keeps its transaction active, under autocommit
too, so commit once the value is read. `free_lob(lob)` ends the locator
sooner; `hold_lob(lob)` keeps it past the commit, until it is freed or a
rollback ends it. A locator no longer valid fails with SQLSTATE 0F001;
`free_lob` and `hold_lob` of a value held whole, which has none, fail
with 22000.

```ruby
conn = Turborel::Client.connect("127.0.0.1", 7422, user: "ann", mechanism: Turborel::Client::Trust.new)
image = conn.query("SELECT IMAGE FROM SCANS").rows.first.first
p conn.in_transaction?
conn.hold_lob(image)
conn.query("COMMIT")
p conn.read_lob(image, 0, 2)
conn.free_lob(image)
begin
  conn.read_lob(image, 0, 2)
rescue Turborel::Error => e
  p [e.sqlcode, e.sqlstate]
end
conn.query("ROLLBACK")
conn.terminate
```

```text
true
"\a\a"
[-301, "0F001"]
```

An import sends a field longer than 64 KiB for a CLOB or BLOB column by
`create_lob`, so no message carries more, as [Copying, Importing and
Exporting](07-copying.md) tells.
