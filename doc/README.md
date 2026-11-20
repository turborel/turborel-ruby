# The turborel-ruby Documentation Set

turborel-ruby is the Ruby driver for Turborel, a relational database
system. It connects a Ruby program to a Turborel server, `turboreld`,
over the server's native protocol, spoken in Ruby alone, and gives the
program a plain API in the manner of the pg gem and an ActiveRecord
adapter for Rails. This set of manuals describes the driver for those who
write programs with it.

turborel-ruby is in alpha: what these manuals describe may change in any
release until 1.0.0 ([Versions](appendix/d-versions.md)). Each change
updates the pages it touches, so the manuals describe the release they
come with. The chapters are written as the driver is built; until then,
each says what it will hold and the milestone that fills it.

## The volumes

| Volume | For | |
|---|---|---|
| [I. User's Guide](user/README.md) | Anyone who writes a Ruby program against Turborel | Installing, connecting, running statements, moving data, chapter by chapter |
| [II. API Reference](client/README.md) | The same, looking something up | The plain API, the ActiveRecord adapter and the low-level client, a page per class or module |
| [Appendices](appendix/README.md) | Everyone | Types, errors, settings, versions |

Read the User's Guide from the start to learn the driver; turn to the API
Reference and the appendices to look a thing up. The reference made from
the code's own documentation is built by `bundle exec rake doc` into
`doc/api/`.

## Conventions

**Examples** of Ruby and of SQL are set in a fixed-width font. Key words
of SQL are in upper case, names in upper case unless delimited, as the
standard folds them:

```sql
SELECT NAME, SALARY FROM STAFF WHERE SALARY > 50000;
```

**Results** of examples follow them, as the program prints them.

**Errors** are given by SQLSTATE, the code the SQL standard defines, and
SQLCODE, the older number. Every error the driver raises is a
`Turborel::Error` that carries both; [Appendix B](appendix/b-errors.md)
lists them.

**Citations** name the section of a Turborel manual a behaviour comes
from: [PROTOCOL Frames] is the section *Frames* of Turborel's *The Native
Protocol*; [CLIENT Pipelines] is the section *Pipelines* of its client
library's chapters.
