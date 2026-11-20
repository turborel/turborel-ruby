# Appendix B: Errors

[Contents](README.md)

Every failure reaches a program as a `Turborel::Error` carrying its
SQLCODE and SQLSTATE. Most come from the server, as it reports them;
some the driver raises itself. This appendix lists the SQLSTATE classes
a program meets, which end the connection, and the failures the driver
raises itself.

## The driver's own failures

The driver raises these itself, each with the SQLCODE and SQLSTATE
turborel-client gives the same case, and the codes every Turborel driver
gives where turborel-client has none.

| SQLSTATE | SQLCODE | When | Ends the connection |
|---|---|---|---|
| 08006 | -919 | A malformed reply (a frame cut short, bytes after its last field, a kind or a value's tag unknown), a frame too long, a reply out of turn (a Ready before SCRAM's server-final among them), the server's answer to Terminate, a direct query's rows Suspended, a compressed frame not granted or damaged, a server that cannot be reached, a failed TLS handshake, a wait past its timeout, a closed connection | yes |
| 08006 | -919 | A method needing a capability the server did not grant, or connection or query attributes past their bounds, more than 32 or one too long, before anything is sent; a write to an export's output that failed, its replies read to their end | no |
| 28000 | -919 | A password or SCRAM over plain TCP; a channel binding required and impossible; a SCRAM server whose final signature is wrong, which does not know the verifier | the connection is not made |
| 08001 | -919 | No server of the settings could be connected to, or a file they name could not be read; no pooled connection came back within the pool's wait | the connection is not made |
| 08002, 08003, 08004, 0A001, 25000, 28000, 2E000, 2A000 | as [The SQL-agent](../client/29-sql-agent.md) lists | A connection statement the SQL-agent refuses | no |
| 26000 | -921 | The plain API's `exec_prepared` or `deallocate` of a name no statement is prepared under, as EXECUTE gives it | no |
| TB916 | -916 | A reply's value whose body cannot be taken, in a frame read whole: a truth or units byte other than 0 or 1, a damaged JSON value, a malformed condition, a value of tag 18 or 19; its request fails, the rest of its replies read past | no |
| 0A000 | -900 | A reply's JSON value nested past 128 or longer than 256 MiB, its request failing as above | no |
| 22003 | -301 | A number or a length out of the range of its field | no |
| 22021 | -301 | A string that cannot be written as UTF-8 | no |
| 22000 | -301 | A value the protocol cannot carry | no |
| 2200N | -301 | An XML value's text that is not well-formed XML content | no |
| 0A000 | -900 | Past Turborel's limits: nesting, a JSON value's size | no |
| TB910 | -910 | The program's misuse where turborel-client has no case: an argument none of those a method takes, a pooled connection asked for after it is released, a row or column a result lacks, the plain API's parameters that are no `Array`, its `transaction` while one is active | no |

## The server's classes

| Class | What | Ends the connection |
|---|---|---|
| 01 | A warning: a statement's completion, a condition, or a notice, as 01T01 when Reset or ChangeUser rolls a transaction back | no |
| 02 | No data: SQLCODE 100, 02000, a statement that found no row | no |
| 07 | A dynamic SQL error: 07001, values short of the parameters | no |
| 08 | A connection exception: 08004, a connection refused; 08006, a connection failure | yes, but 08003 |
| 0A | A feature not supported | no |
| 22 | A data exception: 2200W, a value with no serialization, among the class's states | no |
| 23 | An integrity constraint violation | no |
| 24 | An invalid cursor state: 24000, a cursor open or not as the call needs | no |
| 26 | An invalid SQL statement name: 26000, no such prepared statement | no |
| 28 | Invalid authorization: 28000, credentials refused | as the connection is made |
| 2A | A syntax error or access rule violation | no |
| 37 | A statement that cannot be prepared: 37000 | no |
| 40 | A transaction rollback: 40002, a commit that fails | no |
| TB | Turborel's own: TB920, SQLCODE -920, a statement cancelled; TBR01, a replica that had not applied REPLICATION.READ_AFTER's position in time | no |

A failure that ends the connection leaves it lost: `lost?` is true, and
every request after raises that failure again.

The ActiveRecord adapter raises ActiveRecord's own errors, each caused
by the driver's, as [The ActiveRecord
Adapter](../client/03-api-active-record.md#errors) lists them.
