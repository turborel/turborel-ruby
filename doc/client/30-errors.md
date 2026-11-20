# Errors

[Contents](README.md)

This page will describe the driver's error: its SQLCODE, SQLSTATE and
message, the rule it cites, its position, whether a transaction is still
active, its diagnostics and its cause; and the failures the driver
raises itself, each with the SQLCODE and SQLSTATE turborel-client gives
it. It is filled at milestone M3.

The driver's error is `Turborel::Error` already: each failure the
driver raises carries its SQLCODE and SQLSTATE, its message, and the
rule it cites and its position where known. A frame header that is not
five bytes, or whose body would be longer than the reply limit, fails
with SQLCODE -919 and SQLSTATE 08006, a connection failure.
