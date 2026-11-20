# frozen_string_literal: true

module Turborel
  # Every failure the driver raises, of the server's or its own: SQLCODE,
  # SQLSTATE and message, as turborel reports a failure, with the rule it
  # cites and its position in the statement where known (RULES.md R-ERR-1).
  class Error < StandardError
    # SQLCODE of a connection failure [PROTOCOL Errors and notices].
    CONNECTION_FAILURE_SQLCODE = -919
    # SQLSTATE of a connection failure [PROTOCOL Errors and notices].
    CONNECTION_FAILURE_SQLSTATE = "08006"

    # @return [Integer] the SQLCODE, negative of an error
    attr_reader :sqlcode
    # @return [String] the SQLSTATE, five characters
    attr_reader :sqlstate
    # @return [String, nil] the clause of a standard the failure cites
    attr_reader :rule
    # @return [Integer, nil] where in the statement, counted in characters
    attr_reader :position

    # A failure of SQLCODE, SQLSTATE and message.
    #
    # @param message [String] what went wrong, in plain words
    # @param sqlcode [Integer] the SQLCODE
    # @param sqlstate [String] the SQLSTATE
    # @param rule [String, nil] the clause of a standard it cites
    # @param position [Integer, nil] where in the statement
    def initialize(message, sqlcode:, sqlstate:, rule: nil, position: nil)
      super(message)
      @sqlcode = sqlcode
      @sqlstate = sqlstate
      @rule = rule
      @position = position
    end

    # A failure that loses the connection (SQLCODE -919, SQLSTATE 08006),
    # as a malformed frame does [PROTOCOL Frames].
    #
    # @param message [String] what went wrong, in plain words
    # @return [Error]
    def self.connection_failure(message)
      new(message, sqlcode: CONNECTION_FAILURE_SQLCODE, sqlstate: CONNECTION_FAILURE_SQLSTATE)
    end
  end
end
