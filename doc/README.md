# The turborel-ruby Documentation Set

turborel-ruby is the Ruby driver for Turborel, a relational database
system. It connects a Ruby program to a Turborel server,
`turboreld`, over Turborel's native protocol, version 1, which it speaks
itself, in Ruby alone, with no native extension. Its standard interface is a plain API of connections, results and prepared statements, and an ActiveRecord adapter for Rails 8.1 and later, over a
low-level client built to do all that Turborel's own client library
does. This set of manuals describes it for those who write programs with
it. The SQL a program sends, and the server, are described in Turborel's
own manuals,
[The Turborel Documentation Set](https://github.com/turborel/turborel/blob/main/doc/README.md).

turborel-ruby is in alpha: what these manuals describe may change in any
release until 1.0.0 ([Versions](appendix/d-versions.md)). The driver is
built in milestones, and until a chapter's milestone lands, the chapter
says what it will cover. Each change updates the pages it touches, so
the manuals describe the release they come with.

## The volumes

| Volume | For | |
|---|---|---|
| [I. User's Guide](user/README.md) | Anyone who writes a Ruby program against Turborel | Installing, connecting, queries, prepared statements, transactions, large objects, copying, pipelines and pools, settings and errors, chapter by chapter |
| [II. API Reference](client/README.md) | The same, looking something up | The standard API, then the low-level client, a page for each main interface or module |
| [Appendices](appendix/README.md) | Everyone | Types, errors, settings and versions |

Read the User's Guide from the start to learn the driver; turn to the
API Reference and the appendices to look a thing up.

## Conventions

**Examples** of Ruby and of SQL are set in a fixed-width font.
SQL key words are in upper case, names in upper case unless delimited,
as the standard folds them, and a dynamic parameter is `?`:

```sql
SELECT NAME, SALARY FROM STAFF WHERE SALARY > ?
```

**Results** of examples follow them, as the program prints them.

**Citations** name the section of Turborel's documents a behaviour comes
from: [PROTOCOL Frames] is the section "Frames" of
[The Native Protocol](https://github.com/turborel/turborel/blob/main/doc/client/05-protocol.md);
[CLIENT Pipelines] is the section "Pipelines" of Turborel's client
library chapters,
[The Client Library](https://github.com/turborel/turborel/blob/main/doc/client/02-library.md)
and
[Settings, Pipelines and Pools](https://github.com/turborel/turborel/blob/main/doc/client/02-library-connections.md).
The rows each page fulfils are those of the driver's parity matrix,
[CONFORMANCE.md](../CONFORMANCE.md).

**Errors** are given by SQLSTATE, the code the SQL standard defines, and
SQLCODE, the older number, as Turborel gives them;
[Appendix B](appendix/b-errors.md) maps them to the driver's error.

### Pages of reference

A page of the API Reference has these sections, in this order:

- **NAME**: the interface, class, module or function, and what it does
  in a line.
- **SYNOPSIS**: its declaration, in Ruby.
- **DESCRIPTION**: what it does.
- **ERRORS**: each way it fails, by SQLSTATE.
- **EXAMPLES**: programs, and what they print.
- **STANDARD**: the sections of Turborel's documents it follows, and,
  for the standard API, the specification of the interface.
- **SEE ALSO**: related pages.
