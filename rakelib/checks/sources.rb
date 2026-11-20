# frozen_string_literal: true

module Checks
  # The rules of each source file no linter checks: its length, printing
  # and exits in library code, markers of open work, and each test's
  # citation (RULES.md R-SIZE-2, R-STYLE-3, R-ERR-1, R-DOC-5, R-TRACE-1).
  module Sources
    # The longest a source file may be, in lines (R-SIZE-2).
    MAX_FILE_LINES = 600
    # The files the rules cover: the library, its signatures, its tests and
    # the tools.
    GLOBS = ["lib/**/*.rb", "sig/**/*.rbs", "test/**/*.rb", "rakelib/**/*.rake", "rakelib/**/*.rb",
             "Rakefile", "Gemfile", "Steepfile", "*.gemspec"].freeze
    # Markers of open work, which belongs in the file of open work, never in
    # code (R-DOC-5).
    MARKERS = %w[TODO FIXME XXX].freeze
    # The file of open work, which code never cites (R-DOC-5).
    OPEN_WORK = "#{MARKERS.first}.md".freeze
    # What library code never calls: printing, exiting, a debugger
    # (R-STYLE-3, R-ERR-1).
    FORBIDDEN = /(?<![.\w])(?:puts|print|pp|p|warn|exit!?|abort|binding\.irb|debugger)(?![\w?!])/
    # A string literal, double- or single-quoted.
    STRING = /"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'/
    # A test's citation, the first line of the comment above it: one of
    # D6's tags (R-TRACE-1).
    VERIFIES = /\A\s*# Verifies: \[(?:PROTOCOL [^\]]+\]|CLIENT [^\]]+\]|DESIGN\] D\d+|TOOL\] R-[A-Z]+-\d+)/

    # @return [Array<String>] the source files
    def self.files = Dir.glob(GLOBS)

    # @return [Array<String>] every problem found, as "path:line: what"
    def self.problems
      files.flat_map { |path| file_problems(path, File.readlines(path, chomp: true)) }
    end

    # @return [Array<String>] the problems of one file of +lines+
    def self.file_problems(path, lines)
      found = []
      found << "#{path}: #{lines.size} lines, more than #{MAX_FILE_LINES}" if lines.size > MAX_FILE_LINES
      found.concat(open_work(path, lines))
      found.concat(tests(path, lines)) if path.end_with?("_test.rb")
      found.concat(library(path, lines)) if path.start_with?("lib/")
      found
    end

    # @return [Array<String>] markers of open work in comments, and
    #   citations of the file of open work
    def self.open_work(path, lines)
      marker = /#.*\b(?:#{MARKERS.join("|")})\b/
      lines.each_with_index.flat_map do |line, index|
        [("#{path}:#{index + 1}: a marker of open work in a comment" if line.match?(marker)),
         ("#{path}:#{index + 1}: cites #{OPEN_WORK}" if line.include?(OPEN_WORK))].compact
      end
    end

    # @return [Array<String>] library code that prints, exits or opens a
    #   debugger, comments and string literals aside
    def self.library(path, lines)
      lines.each_with_index.filter_map do |line, index|
        code = line.sub(/\A\s*#.*/, "").gsub(STRING, "\"\"")
        "#{path}:#{index + 1}: prints, exits or opens a debugger" if code.match?(FORBIDDEN)
      end
    end

    # @return [Array<String>] tests whose comment does not begin with
    #   their citation
    def self.tests(path, lines)
      lines.each_with_index.filter_map do |line, index|
        next unless line.match?(/\A\s*def test_/)

        first = lines[0...index].reverse.take_while { |above| above.match?(/\A\s*#/) }.last
        "#{path}:#{index + 1}: a test with no `# Verifies: [...]` citation of D6's tags" unless first&.match?(VERIFIES)
      end
    end
  end
end
