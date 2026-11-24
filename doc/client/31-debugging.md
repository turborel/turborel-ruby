# Debugging Routines

[Contents](README.md)

## NAME

`Turborel::Client::Connection`'s debugger *(extension)*: one connection
driving the routines another connection's session runs.

## SYNOPSIS

```ruby
connection.debug_id                                    # => Integer
connection.debug_attach(id)
connection.debug_break(kind, name, line, schema: "", condition: nil)  # => Debug::Breakpoint
connection.debug_clear(number)
connection.debug_breakpoints                           # => Array<Debug::Breakpoint>
connection.debug_wait(timeout = nil)                   # => Debug::Event, or nil
connection.debug_stack                                 # => Debug::Paused, or nil
connection.debug_resume(action)                        # :into, :over, :out, :continue
connection.debug_interrupt
connection.debug_detach

Turborel::Debug::Breakpoint.new(number:, schema:, name:, line:, condition:)
Turborel::Debug::Event.new(kind:, paused: nil)          # :paused, :timed_out, :cancelled, :ended
Turborel::Debug::Paused.new(reason:, breakpoint:, frames:)   # :breakpoint or :step
Turborel::Debug::Frame.new(origin:, visible:, place:, line:, column:, parameters:, variables:, cursors:)
Turborel::Debug::Origin.new(kind:, specific_schema:, specific_name:, schema:, name:)
Turborel::Debug::Named.new(name:, type:, value:)
Turborel::Debug::Cursor.new(name:, open:, query:)
```

## DESCRIPTION

Where the server grants `debugger`, which a connection asks for unless
told, one connection debugs the session of another
([Debugging Routines](https://github.com/turborel/turborel/blob/main/doc/user/11-debugging.md)).
`debug_id` gives a connection's ID, as INFORMATION_SCHEMA.CONNECTIONS
shows it, and `debug_attach` makes another connection the debugger of
that connection's session. The two are of the same user, unless the
debugger's user is the database's owner or holds the role MONITOR.

`debug_break` sets a breakpoint at a line, from 1, of the text of a
routine of the `kind` given, `:procedure`, `:function` or `:trigger`,
named by its specific name, or by its name if one routine of that kind
has it, or of the trigger of that name. An empty `schema` is the
debugger's session's default schema. Its `condition`, a `<search
condition>` over the frame's parameters and variables, pauses the
target only where it is true. The breakpoint set names its routine by
its specific name. `debug_clear` clears one by its number, and
`debug_breakpoints` lists them in the order they were set. The debugger
pauses in, and sees into, only the routines its user owns or holds
DEBUG on.

`debug_wait` gives the next event of the target, waiting at most
`timeout` seconds, without limit if `nil`, and `nil` if none came. An
event is `:paused`, its `paused` the target's pause, at a breakpoint
or at a step's end, with its call stack, the outermost frame first;
`:timed_out`, paused longer than DEBUGGER.PAUSE_TIMEOUT_MS, it went on
by itself; `:cancelled`, its statement cancelled while it was paused;
or `:ended`, its session ended and the debugger detached. The server
sends an event only between the debugger's requests. One that comes
among a request's replies is kept, never ending them, and `debug_wait`
gives those kept first. A connection over a stream given to `open`, or
a named pipe, waits only without limit.

Each frame names its routine, `origin`, by its specific name and by its
name, `nil` for a statement run directly. A frame the debugger may not
see into is not `visible`, and shows its origin alone. Its `place`
counts characters from the beginning of the routine's text, and its
`line` and `column` count from 1. Its `parameters` and `variables` give
each name, data type as SQL writes it and value, read as a row's value
is; a trigger's parameters are its transition variables. Its `cursors`
give each name, whether it is open, and its query.

`debug_stack` gives the target's pause again, `nil` while it runs.
`debug_resume` lets a paused target go on: `:into` to its next
statement, within a routine it invokes too; `:over` to the next of the
same frame, or of the one it returns to; `:out` to the next of the
frame this one returns to; `:continue` to a breakpoint.
`debug_interrupt` pauses a running target at its next statement.
`debug_detach` ends the debugging: the breakpoints go, a paused target
goes on, and the events kept are dropped.

## ERRORS

Each refusal keeps the session.

| SQLSTATE | SQLCODE | When |
|---|---|---|
| 08003 | -919 | `debug_attach` of an ID whose connection is not served, or whose session the user may not debug |
| 42000 | -104 | `debug_break` in a routine the user neither owns nor holds DEBUG on |
| 42000 | -103 | `debug_break` of no such routine or line |
| TBD01 | -910 | A request the target's state does not allow: `debug_resume` of a target not paused, a second `debug_attach`, or any but `debug_id` and `debug_attach` of a connection attached to none |
| 08006 | -919 | `debugger` not granted, nothing sent; a `timeout` given over a stream that cannot be bounded; the connection kept |
| TB910 | -910 | A `kind` or an `action` none of those named |

## EXAMPLES

```ruby
port = 7422
ann = -> { Turborel::Client.connect("127.0.0.1", port, user: "ann", mechanism: Turborel::Client::Trust.new) }
target = ann.call
debugger = ann.call
target.query("CREATE TABLE STAFF (ID INTEGER PRIMARY KEY, SALARY INTEGER)")
target.query("INSERT INTO STAFF VALUES (1, 50000), (2, 60000)")
target.query(<<~SQL)
  CREATE PROCEDURE RAISE_PAY(IN PCT INTEGER) MODIFIES SQL DATA
  BEGIN
    DECLARE N INTEGER DEFAULT 0;
    UPDATE STAFF SET SALARY = SALARY * (100 + PCT) / 100;
    SET N = (SELECT COUNT(*) FROM STAFF);
  END
SQL
target.query("COMMIT")
debugger.debug_attach(target.debug_id)
set = debugger.debug_break(:procedure, "RAISE_PAY", 4)
p [set.number, set.schema, set.name, set.line, set.condition]
call = Thread.new { target.query("CALL RAISE_PAY(10)").sqlstate }
event = debugger.debug_wait(10)
frame = event.paused.frames.last
p [event.kind, event.paused.reason, frame.origin.name, frame.line, frame.column]
p (frame.parameters + frame.variables).map { [_1.name, _1.type, _1.value] }
debugger.debug_resume(:over)
p debugger.debug_wait(10).paused.frames.last.line
debugger.debug_resume(:continue)
p call.value
debugger.debug_detach
p debugger.debug_wait(0.1)
target.terminate
debugger.terminate
```

```
[1, "ANN", "RAISE_PAY_1", 4, nil]
[:paused, :breakpoint, "RAISE_PAY", 4, 3]
[["PCT", "INTEGER", 10], ["N", "INTEGER", 0]]
5
"00000"
nil
```
