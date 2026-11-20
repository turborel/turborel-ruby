# Turborel::Result

[Contents](README.md)

## NAME

`Turborel::Result`: what a statement of the plain API gave.

## SYNOPSIS

```ruby
result.columns   result.fields   result.nfields   result.ftypes   result.ftype(column)   result.type_written(column)
result.values    result.ntuples  result.each { |row| ... }  result[index]
result.getvalue(row, column)   result.column_values(column)   result.field_values(name)
result.completion   result.cmd_tuples   result.sqlstate
```

## DESCRIPTION

A query's result has its `columns`, each a `Turborel::Column`, whose
names `fields` gives in order, and its rows: `values`, each an `Array`
of a value for each column, as Appendix A maps it; `each`, or
`Enumerable`'s methods, each row as a `Hash` of its columns' names and
values; `result[index]`, one row so; `getvalue`, one value;
`column_values` and `field_values`, one column's values, by its place or
its name, the first column so named. A column with no name, as an
expression's, is named `nil`. `ftypes` gives each column's type's
name as the Information Schema's DATA_TYPE gives it, and `ftype` one
column's: as it was declared, INTEGER or DECIMAL, where the server told
it, else as its data type's tag says, NUMERIC; `type_written` the type
as SQL writes it, as DECIMAL(9,2).

Another statement's result has no columns and no rows, and its
`completion`, the low-level client's `Completion`. `cmd_tuples` gives
the rows the statement inserted, updated, deleted or merged, as the
server tells them, or the rows a query gave; `sqlstate` the
completion's, 02000 of a statement that found no row, 00000 of a query.

## ERRORS

| SQLSTATE | SQLCODE | When |
|---|---|---|
| TB910 | -910 | A row, a column or a column's name the result lacks |

## EXAMPLES

```ruby
conn = Turborel.connect("turborel://ann@127.0.0.1:7422/?tls_mode=disable")
conn.exec("CREATE TABLE CREW2 (ID INTEGER PRIMARY KEY, NAME VARCHAR(10))")
p conn.exec("INSERT INTO CREW2 VALUES (1, 'Ada'), (2, 'Grace')").cmd_tuples
result = conn.exec("SELECT ID, NAME, ID * 10 FROM CREW2 ORDER BY ID")
p result.fields
p result.to_a
p [result.getvalue(1, 1), result.column_values(2), result.field_values("NAME")]
p conn.exec("DELETE FROM CREW2 WHERE ID = 9").sqlstate
conn.exec("ROLLBACK")
conn.close
```

```text
2
["ID", "NAME", nil]
[{"ID"=>1, "NAME"=>"Ada", nil=>10}, {"ID"=>2, "NAME"=>"Grace", nil=>20}]
["Grace", [10, 20], ["Ada", "Grace"]]
"02000"
```

## STANDARD

The driver's own, RULES.md D2.

## SEE ALSO

[Turborel::Connection](01-api-connection.md), [Values](23-values.md),
[Appendix A](../appendix/a-types.md)
