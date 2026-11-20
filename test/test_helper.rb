# frozen_string_literal: true

# What every test file requires first: coverage, when asked for, then
# minitest and the library (RULES.md R-TEST-7).

require "simplecov" if ENV["COVERAGE"]

require "minitest/autorun"
require "turborel"

# Ruby's warnings about lib/ fail the test that set them off, as a lint
# warning fails `rake verify` (RULES.md R-LINT-1).
module WarningsFail
  # A warning about lib/, raised.
  class Raised < StandardError; end

  # The library's directory, which a warning about it names.
  LIB = File.expand_path("../lib", __dir__)

  # Raises a warning about lib/; passes any other on.
  def warn(message, category: nil, **)
    raise Raised, message if message.include?(LIB)

    super
  end
end

Warning[:deprecated] = true
Warning[:performance] = true
Warning.singleton_class.prepend(WarningsFail)

module Turborel
  # What the tests share (RULES.md R-TEST-7).
  module TestSupport
    # SQLCODE and SQLSTATE of a connection failure.
    CONNECTION_FAILURE = [Error::CONNECTION_FAILURE_SQLCODE, Error::CONNECTION_FAILURE_SQLSTATE].freeze
    # SQLCODE and SQLSTATE of a number out of range.
    OUT_OF_RANGE = [Error::DATA_EXCEPTION_SQLCODE, Error::OUT_OF_RANGE_SQLSTATE].freeze
    # SQLCODE and SQLSTATE of a value of no type the driver sends.
    UNSUPPORTED = [Error::DYNAMIC_SQL_SQLCODE, Error::RESTRICTED_TYPE_SQLSTATE].freeze

    # Asserts the block raises a Turborel::Error of +condition+, a pair of
    # SQLCODE and SQLSTATE, and gives it.
    def assert_fails(condition = CONNECTION_FAILURE, &)
      error = assert_raises(Error, &)
      assert_equal condition, [error.sqlcode, error.sqlstate], error.message
      error
    end

    # A Writer, for the bytes a test builds.
    def writer = Protocol::Writer.new

    # A Reader of +bytes+.
    def reader(bytes) = Protocol::Reader.new(bytes, "reply")

    # The bytes of +hex+, written as the spec prints them.
    def hex(text) = [text.delete(" \n")].pack("H*")
  end
end
