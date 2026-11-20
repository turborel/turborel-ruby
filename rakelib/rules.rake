# frozen_string_literal: true

# The checks tool's own rules, those no linter checks (RULES.md D4):
# lengths, printing and exits in library code, markers of open work,
# tests' citations and their targets, the rows marked done each cited by a
# test, and the manual's layout and links.

require_relative "checks/citations"
require_relative "checks/conformance"
require_relative "checks/manual"
require_relative "checks/sources"

desc "Check lengths, printing, open-work markers, citations and the manual (D4, D6, R-DOC-7)"
task :rules do
  problems = Checks::Sources.problems + Checks::Citations.problems + Checks::Conformance.problems +
             Checks::Manual.problems
  abort problems.join("\n") unless problems.empty?
end
