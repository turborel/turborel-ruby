# frozen_string_literal: true

module Turborel
  # What a failure says beyond its SQLSTATE and message, each field +nil+
  # where it says nothing of it [PROTOCOL Errors and notices]: its
  # severity (ERROR, FATAL, WARNING or NOTICE), detail, hint and context,
  # and the schema, table, column, data type and constraint it is about.
  Diagnostics = Data.define(:severity, :detail, :hint, :context, :schema, :table, :column, :data_type, :constraint)

  # A failure as turborel reports one [PROTOCOL Composite fields]: its
  # SQLCODE and SQLSTATE, its message, the rule of a standard it cites, its
  # position in the statement in characters, whether a transaction is
  # still active after it, and its Diagnostics, +nil+ where the server
  # sent none. Turborel::Error carries one.
  Failure = Data.define(:sqlcode, :sqlstate, :message, :rule, :position, :active, :diagnostics)
end
