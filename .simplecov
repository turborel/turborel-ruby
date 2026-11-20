# frozen_string_literal: true

# Coverage of lib/ by the tests, run by `rake coverage` (RULES.md R-COV-1).
# The floors only rise (R-COV-2).
SimpleCov.start do
  enable_coverage :branch
  add_filter "/test/"
  add_filter "/vendor/"
  minimum_coverage line: 95, branch: 90
end
