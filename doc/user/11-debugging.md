# Debugging Routines

[Contents](README.md)

*(extension)* A procedure, a function or a trigger written in SQL can be
run under a debugger: another connection to the same server, which
attaches to the session that runs the routine, sets breakpoints at
lines of its text, and, each time that session pauses, reads its call
stack and tells it how to go on. Turborel's own manual tells who may
debug what
([Debugging Routines](https://github.com/turborel/turborel/blob/main/doc/user/11-debugging.md)).
This chapter tells how a Ruby program does it, on the low-level client
([Debugging Routines](../client/31-debugging.md)).

## Two connections

The session to debug tells its connection's ID, and the debugger
attaches to it. Both are connections of the same user here. The
debugger sets a breakpoint at line 4 of the procedure's text, its
UPDATE. The breakpoint names the procedure by its specific name, as a
routine's name may be overloaded.

The target's CALL pauses as it comes to line 4, and completes only
once the debugger lets it go on, so it runs on a thread of its own.
The debugger waits for the pause, at most 10 seconds here, and reads
the innermost frame: where it is, and its parameters and variables.

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
puts "Breakpoint #{set.number} at #{set.schema}.#{set.name} line #{set.line}."
call = Thread.new { target.query("CALL RAISE_PAY(10)") }
event = debugger.debug_wait(10)
frame = event.paused.frames.last
puts "Paused at breakpoint #{event.paused.breakpoint}, #{frame.origin.name} line #{frame.line}, column #{frame.column}."
(frame.parameters + frame.variables).each { |named| puts "#{named.name} #{named.type} = #{named.value}" }
```

```
Breakpoint 1 at ANN.RAISE_PAY_1 line 4.
Paused at breakpoint 1, RAISE_PAY line 4, column 3.
PCT INTEGER = 10
N INTEGER = 0
```

## Stepping

`debug_resume` lets the paused session go on. `:over` runs the UPDATE
and pauses at the next statement of the same frame, `:into` would
pause within a routine the statement invokes, and `:out` at the next
statement of the frame this one returns to. `:continue` runs to the
next breakpoint, or here to the end of the CALL, which then completes.
`debug_interrupt` pauses a running session at its next statement.

```ruby
debugger.debug_resume(:over)
puts "Paused at line #{debugger.debug_wait(10).paused.frames.last.line}."
debugger.debug_resume(:continue)
puts call.value.sqlstate
debugger.debug_detach
target.terminate
debugger.terminate
```

```
Paused at line 5.
00000
```

A breakpoint may carry a condition over the frame's parameters and
variables, and pauses only where it is true:
`debugger.debug_break(:procedure, "RAISE_PAY", 5, condition: "PCT > 5")`.
`debug_breakpoints` lists the breakpoints, `debug_clear` clears one,
and `debug_stack` gives the paused session's frames again.

## When a pause ends by itself

`debug_wait` gives `nil` if nothing came within its time. Besides a
pause, it may give an event of kind `:timed_out`, a session paused
longer than DEBUGGER.PAUSE_TIMEOUT_MS that went on by itself;
`:cancelled`, its statement cancelled while it was paused; or
`:ended`, its session ended, the debugger detached. A debugger that
detaches, or whose connection ends, lets its session go on as if never
debugged.

A request the debugger may not make is refused, and the session goes
on: an ID of a connection it may not see, SQLSTATE 08003; a breakpoint
in a routine its user neither owns nor holds DEBUG on, 42000; a resume
of a session not paused, or a request of a debugger attached to none,
TBD01.
