# frozen_string_literal: true

require "test_helper"
require_relative "../../server/live_server"

module Turborel
  module Client
    # The routine debugger against a live server, two connections at a
    # time (RULES.md R-TEST-8), skipped without one.
    class LiveDebuggerTest < Minitest::Test
      include TestSupport
      include LiveServer::Case

      # The procedures debugged: DBG_RAISE's UPDATE on line 5, its SET on
      # line 6; DBG_OUTER's CALL of it on line 3, its SET on line 4.
      ROUTINES = [<<~SQL.chomp, <<~SQL.chomp].freeze
        CREATE PROCEDURE DBG_RAISE(IN PCT INTEGER) MODIFIES SQL DATA
        BEGIN
          DECLARE N INTEGER DEFAULT 0;
          DECLARE C CURSOR FOR SELECT ID FROM DBG_STAFF;
          UPDATE DBG_STAFF SET SALARY = SALARY * (100 + PCT) / 100;
          SET N = (SELECT COUNT(*) FROM DBG_STAFF);
        END
      SQL
        CREATE PROCEDURE DBG_OUTER(IN PCT INTEGER) MODIFIES SQL DATA
        BEGIN
          CALL DBG_RAISE(PCT);
          SET PCT = PCT + 1;
        END
      SQL

      # Gives the block a target and its debugger, both ANN's, attached,
      # the procedures made and dropped after.
      def debugging
        connect do |target|
          target.query("CREATE TABLE DBG_STAFF (ID INTEGER PRIMARY KEY, SALARY INTEGER)")
          target.query("INSERT INTO DBG_STAFF VALUES (1, 50000), (2, 60000)")
          ROUTINES.each { target.query(_1) }
          target.query("COMMIT")
          begin
            connect do |debugger|
              debugger.debug_attach(target.debug_id)
              yield target, debugger
            end
          ensure
            target.query("DROP PROCEDURE DBG_OUTER CASCADE")
            target.query("DROP PROCEDURE DBG_RAISE CASCADE")
            target.query("DROP TABLE DBG_STAFF CASCADE")
            target.query("COMMIT")
          end
        end
      end

      # The target's CALL of +sql+, run on a thread of its own.
      def calling(target, sql) = Thread.new { target.query(sql).sqlstate }

      # The innermost frame of +event+'s pause, as its routine, line,
      # parameters, variables and cursors.
      def top(event)
        frame = event.paused.frames.last
        [frame.origin.name, frame.line, frame.parameters.map { [_1.name, _1.type, _1.value] },
         frame.variables.map { [_1.name, _1.value] }, frame.cursors.map { [_1.name, _1.open, _1.query] }]
      end

      # Verifies: [CLIENT Debugging routines] a connection's ID, another of
      # its user's attached to its session; a breakpoint at a line of a
      # procedure, named by its specific name; the target's pause waited
      # for, its call stack read with each frame's parameters, variables
      # and cursors, and read again; a step over to the next line; the
      # target continued to its CALL's end; a wait of nothing, nil; the
      # debugger detached.
      # Verifies: [PROTOCOL Debug 'V'] Debug's identify, attach, break,
      # stack, resume and detach, live.
      # Verifies: [PROTOCOL Event 'W'] Event paused, at a breakpoint and at
      # a step's end, read between requests.
      # Verifies: [PROTOCOL Capabilities] debugger granted, as every
      # connection asks it by default.
      def test_break_pause_step_and_continue
        debugging do |target, debugger|
          set = debugger.debug_break(:procedure, "DBG_RAISE", 5)
          call = calling(target, "CALL DBG_RAISE(10)")
          paused = debugger.debug_wait(10)

          assert debugger.granted?(Protocol::Capabilities::DEBUGGER)
          assert_equal [1, "ANN", "DBG_RAISE_1", 5, nil], set.to_h.values
          assert_equal [:paused, :breakpoint, 1], [paused.kind, paused.paused.reason, paused.paused.breakpoint]
          cursor = ["C", false, "SELECT ID FROM DBG_STAFF"]

          assert_equal ["DBG_RAISE", 5, [["PCT", "INTEGER", 10]], [["N", 0]], [cursor]], top(paused)
          assert_equal [paused.paused, true], [debugger.debug_stack, paused.paused.frames.last.visible]
          debugger.debug_resume(:over)
          stepped = debugger.debug_wait(10)

          assert_equal [:step, nil, 6], [stepped.paused.reason, stepped.paused.breakpoint, top(stepped)[1]]
          debugger.debug_resume(:continue)

          assert_equal ["00000", nil, nil], [call.value, debugger.debug_wait(0.2), debugger.debug_stack]
          debugger.debug_detach
        end
      end

      # Verifies: [CLIENT Debugging routines] breakpoints with and without
      # a condition, listed in the order set, one cleared; a pause where
      # the condition is true alone; a step into the procedure a CALL
      # invokes, its frames the outermost first, and out of it to the
      # caller's next line; a running target interrupted, pausing at its
      # next statement.
      def test_conditions_steps_and_interrupt
        debugging do |target, debugger|
          never = debugger.debug_break(:procedure, "DBG_RAISE", 5, condition: "PCT > 50")
          outer = debugger.debug_break(:procedure, "DBG_OUTER", 3, schema: "ANN", condition: "PCT > 5")

          assert_equal([[never.number, "PCT > 50"], [outer.number, "PCT > 5"]],
                       debugger.debug_breakpoints.map { [_1.number, _1.condition] })
          debugger.debug_clear(never.number)

          assert_equal [outer], debugger.debug_breakpoints
          call = calling(target, "CALL DBG_OUTER(10)")

          assert_equal ["DBG_OUTER", 3], top(debugger.debug_wait(10)).first(2)
          debugger.debug_resume(:into)
          into = debugger.debug_wait(10)

          assert_equal [%w[DBG_OUTER DBG_RAISE], 5], [into.paused.frames.map { _1.origin.name }, top(into)[1]]
          debugger.debug_resume(:out)

          assert_equal ["DBG_OUTER", 4], top(debugger.debug_wait(10)).first(2)
          debugger.debug_clear(outer.number)
          debugger.debug_resume(:continue)

          assert_equal "00000", call.value
          debugger.debug_interrupt
          call = calling(target, "CALL DBG_RAISE(1)")
          interrupted = debugger.debug_wait(10)

          assert_equal [:step, "DBG_RAISE"], [interrupted.paused.reason, top(interrupted).first]
          debugger.debug_resume(:continue)

          assert_equal "00000", call.value
        end
      end

      # Verifies: [PROTOCOL Debug 'V'] refusals that keep the session: an ID
      # whose connection the user may not see, 08003; a breakpoint in a
      # routine the user holds no DEBUG on, 42000 (SQLCODE -104); a resume
      # of a target not paused, a second attach, or a request of a
      # connection attached to none, TBD01 (SQLCODE -910).
      # Verifies: [PROTOCOL Event 'W'] Event ended, of a target whose
      # session ends, the debugger detached.
      # Verifies: [CLIENT Debugging routines] the target's end waited for.
      def test_refusals_and_the_end
        debugging do |target, debugger|
          id = target.debug_id
          refused = [-910, "TBD01"]

          assert_fails(refused) { debugger.debug_resume(:continue) }
          assert_fails(refused) { debugger.debug_attach(id) }
          connect(user: "bob") do |bob|
            assert_fails([-919, "08003"]) { bob.debug_attach(id) }
            assert_fails(refused) { bob.debug_stack }
            connect(user: "bob") { |own| bob.debug_attach(own.debug_id) }

            assert_equal :ended, bob.debug_wait(10).kind
            assert_fails(refused) { bob.debug_stack }
            connect(user: "bob") do |own|
              bob.debug_attach(own.debug_id)

              assert_fails([-104, "42000"]) { bob.debug_break(:procedure, "DBG_RAISE", 5, schema: "ANN") }
              assert_empty bob.debug_breakpoints
            end
          end
          debugger.debug_detach
        end
      end
    end
  end
end
