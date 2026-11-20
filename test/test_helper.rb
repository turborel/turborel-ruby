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
