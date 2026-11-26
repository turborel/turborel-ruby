# frozen_string_literal: true

module Turborel
  module Protocol
    # The capabilities of version 1 [PROTOCOL Capabilities]: a client asks
    # for them by name in Hello, and Ready grants those the server has, in
    # this order.
    #
    # @api private
    module Capabilities
      # Each capability's name [PROTOCOL Capabilities].
      NOTICES = "notices"
      # (see NOTICES)
      STATUS = "status"
      # (see NOTICES)
      DIAGNOSTICS = "diagnostics"
      # (see NOTICES)
      DESCRIBE = "describe"
      # (see NOTICES)
      CURSORS = "cursors"
      # (see NOTICES)
      PING = "ping"
      # (see NOTICES)
      RESET = "reset"
      # (see NOTICES)
      CHANGE_USER = "change-user"
      # (see NOTICES)
      QUERY_ATTRIBUTES = "query-attributes"
      # (see NOTICES)
      CONNECTION_ATTRIBUTES = "connection-attributes"
      # (see NOTICES)
      MULTI_STATEMENT = "multi-statement"
      # (see NOTICES)
      COMPRESSION = "compression"
      # (see NOTICES)
      COMMIT_POSITION = "commit-position"
      # (see NOTICES)
      COPY = "copy"
      # (see NOTICES)
      ROW_COUNTS = "row-counts"
      # (see NOTICES)
      GENERATED_VALUES = "generated-values"
      # (see NOTICES)
      FETCH_ENDS = "fetch-ends"
      # (see NOTICES)
      CONDITIONS = "conditions"
      # (see NOTICES)
      DECLARED_TYPES = "declared-types"
      # (see NOTICES)
      PARAMETER_MODES = "parameter-modes"
      # (see NOTICES)
      DEBUGGER = "debugger"
      # (see NOTICES)
      COLUMNS = "columns"
      # Every capability, in the table's order.
      ALL = [NOTICES, STATUS, DIAGNOSTICS, DESCRIBE, CURSORS, PING, RESET, CHANGE_USER, QUERY_ATTRIBUTES,
             CONNECTION_ATTRIBUTES, MULTI_STATEMENT, COMPRESSION, COMMIT_POSITION, COPY, ROW_COUNTS,
             GENERATED_VALUES, FETCH_ENDS, CONDITIONS, DECLARED_TYPES, PARAMETER_MODES, DEBUGGER,
             COLUMNS].freeze

      # The capabilities among +names+ this side knows, in the table's
      # order; others left out, as turborel's Capabilities::of leaves them.
      #
      # @param names [Array<String>]
      # @return [Array<String>]
      def self.known(names) = ALL & names
    end
  end
end
