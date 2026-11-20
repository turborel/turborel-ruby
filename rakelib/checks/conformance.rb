# frozen_string_literal: true

module Checks
  # A row of CONFORMANCE.md marked done is tested by a test citing its
  # section (RULES.md R-TRACE-4): its citation begins some test's
  # `# Verifies:` line.
  module Conformance
    # A row: its ID, its citation, and its status.
    ROW = /^\| ([A-Z]+-[A-Z]+-\d+) \|.*\| `(\[[^`]+)` \| (done|not yet) \|$/
    # A test's citation, after `# Verifies: `.
    CITED = /# Verifies: (\[(?:PROTOCOL|CLIENT) [^\]]+\]|\[DESIGN\] D\d+|\[TOOL\] R-[A-Z]+-\d+)/

    # @return [Array<String>] the rows marked done that no test cites
    def self.problems
      cited = Dir.glob("test/**/*_test.rb").flat_map { |path| File.read(path).scan(CITED).flatten }.uniq
      File.readlines("CONFORMANCE.md", chomp: true).filter_map do |line|
        id, citation, status = line.match(ROW)&.captures
        "CONFORMANCE.md: #{id} is done, but no test cites #{citation}" if status == "done" && !cited.include?(citation)
      end
    end
  end
end
