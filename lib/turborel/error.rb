# frozen_string_literal: true

module Turborel
  # Every failure the driver raises, of the server's or its own, carrying
  # the Failure that says what went wrong (RULES.md R-ERR-1).
  class Error < StandardError
    # SQLCODE of a connection failure [PROTOCOL Errors and notices].
    CONNECTION_FAILURE_SQLCODE = -919
    # SQLSTATE of a connection failure [PROTOCOL Errors and notices].
    CONNECTION_FAILURE_SQLSTATE = "08006"
    # SQLCODE of a data exception, as turborel numbers its exceptions.
    DATA_EXCEPTION_SQLCODE = -301
    # SQLSTATE of a number out of the range of its type or field.
    OUT_OF_RANGE_SQLSTATE = "22003"
    # SQLSTATE of a string with a character its encoding cannot hold:
    # character not in repertoire.
    NOT_IN_REPERTOIRE_SQLSTATE = "22021"
    # SQLCODE of a dynamic SQL error, as turborel numbers its exceptions.
    DYNAMIC_SQL_SQLCODE = -921
    # SQLSTATE of a parameter of no type the driver can send: restricted
    # data type attribute violation.
    RESTRICTED_TYPE_SQLSTATE = "07006"

    # @return [Failure] what went wrong
    attr_reader :failure

    # An error of +failure+.
    #
    # @param failure [Failure] what went wrong
    def initialize(failure)
      super(failure.message)
      @failure = failure
    end

    # @return [Integer] the SQLCODE, negative of an exception
    def sqlcode = failure.sqlcode

    # @return [String] the SQLSTATE, five characters
    def sqlstate = failure.sqlstate

    # @return [String, nil] the clause of a standard the failure cites
    def rule = failure.rule

    # @return [Integer, nil] where in the statement, counted in characters
    def position = failure.position

    # @return [Boolean] whether a transaction is active after it
    def active = failure.active

    # @return [Diagnostics, nil] what the server said beyond the message
    def diagnostics = failure.diagnostics

    # An error the driver raises itself, of SQLCODE, SQLSTATE and message.
    #
    # @param sqlcode [Integer] the SQLCODE
    # @param sqlstate [String] the SQLSTATE
    # @param message [String] what went wrong, in plain words
    # @return [Error]
    def self.of(sqlcode, sqlstate, message)
      new(Failure.new(sqlcode:, sqlstate:, message:, rule: nil, position: nil, active: false, diagnostics: nil))
    end

    # A failure that loses the connection (SQLCODE -919, SQLSTATE 08006),
    # as a malformed message does [PROTOCOL Errors and notices].
    #
    # @param message [String] what went wrong, in plain words
    # @return [Error]
    def self.connection_failure(message)
      of(CONNECTION_FAILURE_SQLCODE, CONNECTION_FAILURE_SQLSTATE, message)
    end

    # A number, or a length, out of the range of the field it is written
    # to (SQLCODE -301, SQLSTATE 22003).
    #
    # @param message [String] what went wrong, in plain words
    # @return [Error]
    def self.out_of_range(message)
      of(DATA_EXCEPTION_SQLCODE, OUT_OF_RANGE_SQLSTATE, message)
    end

    # A string that cannot be written as UTF-8 (SQLCODE -301, SQLSTATE
    # 22021).
    #
    # @param message [String] what went wrong, in plain words
    # @return [Error]
    def self.not_in_repertoire(message)
      of(DATA_EXCEPTION_SQLCODE, NOT_IN_REPERTOIRE_SQLSTATE, message)
    end

    # A value of no type the driver can send (SQLCODE -921, SQLSTATE
    # 07006).
    #
    # @param message [String] what went wrong, in plain words
    # @return [Error]
    def self.unsupported(message)
      of(DYNAMIC_SQL_SQLCODE, RESTRICTED_TYPE_SQLSTATE, message)
    end
  end
end
