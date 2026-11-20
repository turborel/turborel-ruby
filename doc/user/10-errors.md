# Errors

[Contents](README.md)

This chapter will tell what a failure carries, its SQLCODE, SQLSTATE, message and diagnostics, how a program tells a lost connection from a failed statement, and how warnings and notices reach it. Every failure the driver raises is already a `Turborel::Error`, with SQLCODE and SQLSTATE; the rest of the chapter is filled by milestone M3.
