# frozen_string_literal: true

module Turborel
  # Every failure the driver raises, of the server's or its own, carrying
  # the Failure that says what went wrong (RULES.md R-ERR-1).
  class Error < StandardError
    # SQLCODE of a connection failure [PROTOCOL Errors and notices].
    CONNECTION_FAILURE_SQLCODE = -919
    # SQLSTATE of a connection failure [PROTOCOL Errors and notices].
    CONNECTION_FAILURE_SQLSTATE = "08006"
    # SQLSTATE of credentials refused: invalid authorization
    # specification.
    INVALID_AUTHORIZATION_SQLSTATE = "28000"
    # SQLCODE of a data exception, as turborel numbers its exceptions.
    DATA_EXCEPTION_SQLCODE = -301
    # SQLSTATE of a number out of the range of its type or field.
    OUT_OF_RANGE_SQLSTATE = "22003"
    # SQLSTATE of a string with a character its encoding cannot hold:
    # character not in repertoire.
    NOT_IN_REPERTOIRE_SQLSTATE = "22021"
    # SQLSTATE of a data exception of no more specific state: a value the
    # protocol cannot carry.
    DATA_EXCEPTION_SQLSTATE = "22000"
    # SQLCODE of what is past turborel's limits, as turborel numbers it.
    BEYOND_SQLCODE = -900
    # SQLSTATE of what is past turborel's limits: feature not supported.
    FEATURE_NOT_SUPPORTED_SQLSTATE = "0A000"
    # SQLCODE of a value whose body cannot be taken, turborel's corrupt
    # data's.
    CORRUPT_SQLCODE = -916
    # SQLSTATE of a value whose body cannot be taken.
    CORRUPT_SQLSTATE = "TB916"
    # SQLCODE of the program's misuse of the driver, turborel's API code.
    MISUSED_SQLCODE = -910
    # SQLSTATE of the program's misuse of the driver.
    MISUSED_SQLSTATE = "TB910"

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

    # An error the driver raises itself, of SQLCODE, SQLSTATE and message,
    # and the rule of a standard it cites, if it cites one, kept apart.
    #
    # @param sqlcode [Integer] the SQLCODE
    # @param sqlstate [String] the SQLSTATE
    # @param message [String] what went wrong, in plain words
    # @param rule [String, nil] the rule it cites
    # @return [Error]
    def self.of(sqlcode, sqlstate, message, rule: nil)
      new(Failure.new(sqlcode:, sqlstate:, message:, rule:, position: nil, active: false, diagnostics: nil))
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

    # A value the protocol cannot carry: of no class the driver sends, or
    # of a field none of the protocol's (SQLCODE -301, SQLSTATE 22000).
    #
    # @param message [String] what went wrong, in plain words
    # @return [Error]
    def self.data_exception(message)
      of(DATA_EXCEPTION_SQLCODE, DATA_EXCEPTION_SQLSTATE, message)
    end

    # What is past turborel's limits: values nested too deep, a JSON
    # document too long, too many attributes or too long a one (SQLCODE
    # -900, SQLSTATE 0A000), as turborel's own code says.
    #
    # @param message [String] what went wrong, in plain words
    # @return [Error]
    def self.beyond(message)
      of(BEYOND_SQLCODE, FEATURE_NOT_SUPPORTED_SQLSTATE, message)
    end

    # A value of a reply whose body the driver cannot take, in a frame read
    # whole (SQLCODE -916, SQLSTATE TB916): it fails its request alone, the
    # connection kept [PROTOCOL Values and fields].
    #
    # @param message [String] what went wrong, in plain words
    # @return [Error]
    def self.corrupt_value(message)
      of(CORRUPT_SQLCODE, CORRUPT_SQLSTATE, message)
    end

    # The program's misuse of the driver, where turborel-client has no
    # case of its own: an argument none of those a method takes (SQLCODE
    # -910, SQLSTATE TB910).
    #
    # @param message [String] what went wrong, in plain words
    # @return [Error]
    def self.misused(message)
      of(MISUSED_SQLCODE, MISUSED_SQLSTATE, message)
    end
  end
end
