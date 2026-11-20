# Copy, Import and Export

[Contents](README.md)

## NAME

`Turborel::Client::Connection#copy_in`, `#copy_rows` and `#export`;
`Turborel::Import`: rows copied in bulk, imported from a source, and a
query's rows exported.

## SYNOPSIS

```ruby
connection.copy_in(table, columns = [])                  # => Copying
connection.copy_in(table, columns = []) { |copy| ... }   # => Integer, the rows inserted
connection.copy_rows(table, columns, rows)               # => Integer
copy << row   copy.finish   # => Integer   copy.abandon   copy.ended?
connection.export(sql, out, format = :csv)               # => Integer, of :csv or :native
Turborel::Client::Export.read_native(input)              # => [columns, rows]

Turborel::Import.run(connection, source, options) { |rejected| ... } # => Imported
Turborel::Import::Options.into(table)    # .with(batch:, skip:)
Turborel::Import::Delimited.new(io, dialect = Dialect.csv)
Turborel::Import::Dialect.csv | .tsv     # .with_header .with_null(text) .with_delimiter(char) .with_max_record(bytes)
Turborel::Import::Imported   # rows, rejected
Turborel::Import::Rejected   # position, failure, input
Turborel::Import::ImportError < Turborel::Error  # position, committed, rolled_back, input
Turborel::Import::Position   # record, line
Turborel::Import::Heading    # name, type
Turborel::Import::Record     # values, position
Turborel::Import::SourceError # position, message
```

## DESCRIPTION

`copy_in` begins a copy into a table, as SQL names it, of the columns
named or all, the copy its transaction's own under autocommit; within a
transaction, one that fails is undone alone. `<<` sends a row, an
`Array` of a value for each column, many to a message once they are
about 256 KiB; `finish` ends the copy, giving the rows inserted;
`abandon` undoes every row. A copy is all or nothing: a row refused
undoes every row, its failure's detail naming the row, as `row 7 of the
copy`. A block's copy finishes as the block ends and is abandoned if it
raises. Until a copy ends the connection sends only its rows, its end and
Ping. `copy_rows` copies the rows an enumerable gives.

`Import.run` inserts a source's records into the table its options name,
through one prepared INSERT, or by copy where the server grants `copy`,
no row is to be skipped and no column is a large object. A source
answers `headings`, a `Heading` of each field or `nil`, asked once, then
`record`, the next `Record` or `nil`; it raises `SourceError` where it
cannot be read. `Delimited` reads CSV and tab-separated text a record at
a time, refusing one past its longest, 16 MiB by default. A heading
names the column of the identifier it is, else of its text as written.
Each value is cast to its column's type, a string for a character string
column assigned as INSERT assigns it, and a field longer than 64 KiB for
a large object column sent ahead by `create_lob`. A batch of rows,
1000 unless told, 0 for all, is committed at a time. A row that fails
stops the import, the batch under way rolled back, or with `skip` is
given to the block and the rest imported.

`export` runs a query and writes its rows as they come: as CSV, a header
then a record for each row ended by CR LF, each value as Turborel shows
it; or as the protocol's own frames, a Description, Rows and a Complete,
which `read_native` reads back with every value as it was.

## ERRORS

| SQLSTATE | SQLCODE | When |
|---|---|---|
| the server's | the server's | A copy's failure from `finish`, every row undone: a table or column not found, a row of too many or too few values, a value its column refuses |
| 22000 | -301 | An import's source that cannot be read, or a record of too many or too few fields: the `ImportError`'s cause, `input` true |
| 22001 | -301 | A string too long for its character string column |
| TB910 | -910 | Another request while a copy is under way; a copy used after it ended; a delimiter that is not one ASCII character other than a quote or a line break; an export's format other than `:csv` and `:native` |
| 08006 | -919 | `copy_in` without `copy` granted, before anything is sent; an export of a statement that is no query, or a write to `out` that failed; input to `read_native` that is not native rows |

An `ImportError` says where its record began, why, how many rows were
committed and how many of the batch rolled back; it is refused before
any row, with nothing committed, in a transaction active or of a table
not named as a `<table name>`.

## EXAMPLES

```ruby
require "stringio"

conn = Turborel::Client.connect("127.0.0.1", 7422, user: "ann", mechanism: Turborel::Client::Trust.new)
conn.query("CREATE TABLE TEAM (ID INTEGER PRIMARY KEY, NAME VARCHAR(5))")
conn.query("COMMIT")
skipped = []
tsv = StringIO.new("1\tAda\n2\tGrace Hopper\n3\t\\N\n")
source = Turborel::Import::Delimited.new(tsv, Turborel::Import::Dialect.tsv.with_null("\\N"))
options = Turborel::Import::Options.into("TEAM").with(skip: true)
p Turborel::Import.run(conn, source, options) { |row| skipped << row.to_s }
puts skipped
conn.terminate
```

```text
#<data Turborel::Import::Imported rows=2, rejected=1>
record 2, line 2: SQLCODE -301 (SQLSTATE 22001): a value of 12 characters, not spaces beyond 5, does not fit CHARACTER VARYING(5) [ISO/IEC 9075:1992 §13.8 GR4b iii, §9.2 GR3e ii]; skipped
```

## STANDARD

[PROTOCOL CopyIn 'I'], [PROTOCOL CopyData 'J'] and [PROTOCOL CopyEnd
'N'] of [The Native
Protocol](https://github.com/turborel/turborel/blob/main/doc/client/05-protocol.md);
[CLIENT Copying and exporting] and [CLIENT Importing] of [The Client
Library](https://github.com/turborel/turborel/blob/main/doc/client/02-library.md).

## SEE ALSO

[Copying, Importing and Exporting](../user/07-copying.md), [Large
Objects](24-large-objects.md), [Errors](30-errors.md)
