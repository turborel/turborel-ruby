# Copying, Importing and Exporting

[Contents](README.md)

This chapter tells how a program copies rows into a table in bulk, all
or nothing; imports CSV and tab-separated text; and exports a query's
rows as CSV or as the protocol's own frames.

## Copying

`copy_in(table, columns)` begins a copy into `table`, as SQL names it,
of the columns named, in order, or all of them. The copy's `<<` sends a
row, an `Array` of a value for each column, many rows to a message and
no reply each; `finish` ends it, giving the rows inserted. Each value is
assigned to its column as INSERT assigns it. A copy is all or nothing: a
row refused undoes every row of it, the failure's detail naming the row,
as `row 3 of the copy`. Within a transaction, a copy that fails is
undone alone, the transaction going on; under autocommit the copy is its
own transaction. Given a block, `copy_in` finishes the copy as the
block ends, and abandons it if the block raises; `abandon` gives it up,
every row undone. While a copy is under way the connection sends
nothing else but `ping`: any other request fails, SQLSTATE TB910.
`copy_rows(table, columns, rows)` copies the rows an enumerable gives.

```ruby
conn = Turborel::Client.connect("127.0.0.1", 7422, user: "ann", mechanism: Turborel::Client::Trust.new)
conn.query("CREATE TABLE STAFF (ID INTEGER PRIMARY KEY, NAME VARCHAR(20))")
conn.query("COMMIT")
p conn.copy_rows("STAFF", %w[ID NAME], [[7, "Niklaus"], [8, "Barbara"]])
begin
  conn.copy_in("STAFF") { |copy| copy << [9, "Ken"] << [7, "again"] }
rescue Turborel::Error => e
  p [e.sqlstate, e.diagnostics.detail]
end
p conn.query("SELECT COUNT(*) FROM STAFF").rows
conn.query("COMMIT")
conn.terminate
```

```text
2
["23000", "row 2 of the copy"]
[[2]]
```

## Importing

`Turborel::Import.run(connection, source, options)` inserts the records
of a source into a table. A source is any object that answers
`headings`, its fields' names, and types if it knows them, or `nil`;
then `record`, each record, a `Turborel::Import::Record` of its values
and where it began, until it gives `nil`. It holds a record at a time,
so a source of any size is read in bounded memory.
`Turborel::Import::Delimited` reads CSV, `Dialect.csv`, or
tab-separated text, `Dialect.tsv`, from any IO, with a header, a
delimiter and a text for null as its dialect says.

`Options.into(table)` imports into `table`, 1000 rows committed at a
time; `with(batch:)` commits so many, 0 all at once, and `with(skip:
true)` skips a row that fails, each given to the block. A heading names
the column of the identifier it is, so `name` names NAME; without
headings, the fields go into the table's columns in order. Each value is
cast to its column's type by the server, but a string for a character
string column is assigned to it as INSERT assigns, so one too long is
refused, SQLSTATE 22001. The session must have no transaction active,
as an import commits its batches. Where the server grants `copy`, no
row is to be skipped and no column is a large object, the import goes
by copy.

A row that fails ends the import with a `Turborel::Import::ImportError`:
where its record began, why, its failure the source's (SQLSTATE 22000)
or SQL's, how many rows were committed and how many of the batch rolled
back.

```ruby
require "stringio"

conn = Turborel::Client.connect("127.0.0.1", 7422, user: "ann", mechanism: Turborel::Client::Trust.new)
csv = StringIO.new("id,name\n1,Ada\n2,\"Hopper, Grace\"\n")
source = Turborel::Import::Delimited.new(csv, Turborel::Import::Dialect.csv.with_header)
p Turborel::Import.run(conn, source, Turborel::Import::Options.into("STAFF"))
bad = StringIO.new("3,Edsger\nfour,Tony\n")
begin
  Turborel::Import.run(conn, Turborel::Import::Delimited.new(bad), Turborel::Import::Options.into("STAFF"))
rescue Turborel::Import::ImportError => e
  puts e.message
end
conn.terminate
```

```text
#<data Turborel::Import::Imported rows=2, rejected=0>
record 2, line 2: SQLCODE -301 (SQLSTATE 22018): 'four' is not a <signed numeric literal> [ISO/IEC 9075:1992 §6.10 GR3b i, GR4b i]; 0 rows committed, 1 rolled back
```

## Exporting

`export(sql, out, format)` runs a query and writes its rows to `out`,
anything that takes `write`, as they come. As `:csv`, the default: a
header of the columns' names, then a record for each row, each ended by
CR LF, each value as Turborel shows it, a field quoted where it holds a
comma, a quote, a line break or spaces at either end, a null an empty
field and an empty string `""`. As `:native`, the protocol's own frames,
which `Turborel::Client::Export.read_native` reads back with every value
as it was.

```ruby
require "stringio"

conn = Turborel::Client.connect("127.0.0.1", 7422, user: "ann", mechanism: Turborel::Client::Trust.new)
out = StringIO.new
p conn.export("SELECT ID, NAME FROM STAFF ORDER BY ID", out)
puts out.string.split("\r\n")
native = StringIO.new
conn.export("SELECT ID, NAME FROM STAFF ORDER BY ID", native, :native)
columns, rows = Turborel::Client::Export.read_native(native.string)
p columns.map(&:name), rows.first
conn.query("COMMIT")
conn.terminate
```

```text
4
ID,NAME
1,Ada
2,"Hopper, Grace"
7,Niklaus
8,Barbara
["ID", "NAME"]
[1, "Ada"]
```
