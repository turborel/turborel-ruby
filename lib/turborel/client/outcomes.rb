# frozen_string_literal: true

module Turborel
  module Client
    # A query's outcome [CLIENT Running statements]: its columns, each a
    # Column, and its rows, each an Array of a value for each column.
    Rows = Data.define(:columns, :rows)

    # Any other statement's outcome, its completion [PROTOCOL Complete
    # 'K']: SQLCODE 0 or 100, SQLSTATE, a warning's among them, whether a
    # transaction is active after it, and what the server granted it to
    # tell: the commit's position, the rows it counted, the identity values
    # it generated, its conditions and the server's Timing.
    Completion = Protocol::Replies::Complete

    # The server's time for a statement, in microseconds [CLIENT What the
    # server tells]: total, queued for a worker, waiting for locks.
    Timing = Protocol::Replies::Timing

    # A condition a statement raised, or a notice of the server's own
    # [PROTOCOL Notice 'N']: its SQLSTATE, message and Diagnostics.
    Notice = Protocol::Replies::Notice

    # A statement the server prepared [CLIENT Prepared statements]: the
    # client's +number+ for it, its +parameters+, each a Parameter in the
    # order of its ? mark, and its +columns+ of a query, none of another.
    Statement = Data.define(:number, :parameters, :columns)

    # Rows of a cursor, and whether it has more, which fetch reads; closed
    # if not [CLIENT Prepared statements].
    Batch = Data.define(:rows, :more)

    # What a text of several statements gave [CLIENT Controlling the
    # session]: each statement's outcome, Rows or a Completion, in order,
    # and the Failure of the one that stopped the rest, +nil+ if none did.
    Ran = Data.define(:outcomes, :failure)
  end
end
