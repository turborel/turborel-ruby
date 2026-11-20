# frozen_string_literal: true

# The rules no linter checks, as main's `cargo xtask verify` checks its
# own (RULES.md R-SIZE-2, R-STYLE-5, R-ERR-3, R-DOC-5, R-DOC-7,
# R-TRACE-1, R-TRACE-2).
module Rules
  # The longest a source file may be, in lines (R-SIZE-2).
  MAX_FILE_LINES = 600
  # The files the rules cover: the library, its signatures, its tests and
  # the tools.
  SOURCES = ["lib/**/*.rb", "sig/**/*.rbs", "test/**/*.rb", "rakelib/*.rake",
             "Rakefile", "Gemfile", "Steepfile", "*.gemspec"].freeze
  # Markers of open work, which belongs in the file of open work, never in
  # code (R-DOC-5).
  MARKERS = %w[TODO FIXME XXX HACK].freeze
  # The file of open work, which code never cites (R-DOC-5).
  OPEN_WORK = "#{MARKERS.first}.md".freeze
  # What library code never calls: printing, exiting, a debugger
  # (R-STYLE-5, R-ERR-3).
  FORBIDDEN = /(?<![.\w])(?:puts|print|pp|p|warn|exit!?|abort|binding\.irb|debugger)(?![\w?!])/
  # A string literal, double- or single-quoted.
  STRING = /"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'/
  # A test's citation, the first line of the comment above it (R-TRACE-1).
  VERIFIES = /\A\s*# Verifies: \[(?:PROTOCOL [^\]]+|CLIENT [^\]]+|DESIGN|RFC \d+[^\]]*)\]/
  # A citation of the manual: the spec, or the client library's chapters.
  CITATION = /\[(PROTOCOL|CLIENT) ([^\]]+)\]/
  # The documents whose relative links must resolve (R-DOC-7).
  DOCUMENTS = ["*.md", "doc/**/*.md", ".github/**/*.md"].freeze
  # A Markdown link's target.
  LINK = /\]\(([^)\s]+)\)/
  # A target that is not a file of the repository: a URL or an anchor.
  EXTERNAL = /\A(?:[a-z]+:|#)/
  # The chapters of main's doc/client/ each citation names (R-TRACE-2).
  CHAPTERS = { "PROTOCOL" => ["05-protocol.md"], "CLIENT" => ["02-library.md", "02-library-connections.md"] }.freeze

  # Every problem found in the files, as "path:line: what".
  def self.problems
    files = Dir.glob(SOURCES)
    files.flat_map { |path| file_problems(path, File.readlines(path, chomp: true)) }
  end

  # The problems of one file of +lines+.
  def self.file_problems(path, lines)
    found = []
    found << "#{path}: #{lines.size} lines, more than #{MAX_FILE_LINES}" if lines.size > MAX_FILE_LINES
    found.concat(open_work_problems(path, lines))
    found.concat(test_problems(path, lines)) if path.end_with?("_test.rb")
    found.concat(library_problems(path, lines)) if path.start_with?("lib/")
    found
  end

  # Markers of open work in comments, and citations of the file of open
  # work (R-DOC-5).
  def self.open_work_problems(path, lines)
    marker = /#.*\b(?:#{MARKERS.join("|")})\b/
    lines.each_with_index.flat_map do |line, index|
      [("#{path}:#{index + 1}: a marker of open work in a comment" if line.match?(marker)),
       ("#{path}:#{index + 1}: cites #{OPEN_WORK}" if line.include?(OPEN_WORK))].compact
    end
  end

  # Library code that prints, exits or opens a debugger, comments and
  # string literals aside.
  def self.library_problems(path, lines)
    lines.each_with_index.filter_map do |line, index|
      code = line.sub(/\A\s*#.*/, "").gsub(STRING, "\"\"")
      "#{path}:#{index + 1}: prints, exits or opens a debugger" if code.match?(FORBIDDEN)
    end
  end

  # A test whose comment does not begin with its citation.
  def self.test_problems(path, lines)
    lines.each_with_index.filter_map do |line, index|
      next unless line.match?(/\A\s*def test_/)

      first = lines[0...index].reverse.take_while { |above| above.match?(/\A\s*#/) }.last
      "#{path}:#{index + 1}: a test with no `# Verifies: [...]` comment" unless first&.match?(VERIFIES)
    end
  end

  # Relative links in the documents to files that do not exist (R-DOC-7).
  def self.link_problems
    Dir.glob(DOCUMENTS).flat_map do |path|
      File.read(path).scan(LINK).flatten.filter_map do |target|
        next if target.match?(EXTERNAL)

        file = File.expand_path(target.sub(/#.*/, ""), File.dirname(path))
        "#{path}: the link #{target} resolves to no file" unless File.exist?(file)
      end
    end
  end

  # Citations of headings not in main's manual, read from +dir+, its
  # doc/client/ (R-TRACE-2).
  def self.citation_problems(dir)
    headings = headings_in(dir)
    Dir.glob(SOURCES).flat_map do |path|
      File.read(path).scan(CITATION).filter_map do |book, heading|
        "#{path}: [#{book} #{heading}] is no heading of the manual" unless headings.fetch(book).include?(heading)
      end
    end
  end

  # Each book's headings, from the chapters in +dir+.
  def self.headings_in(dir)
    CHAPTERS.transform_values do |chapters|
      chapters.flat_map { |name| File.readlines(File.join(dir, name), chomp: true).grep(/\A#+ /) }
              .map { |heading| heading.sub(/\A#+ /, "") }
    end
  end
end

desc "Check file length, printing and exits, open-work markers, links and citations (R-SIZE-2, R-DOC-5, R-DOC-7)"
task :rules do
  problems = Rules.problems + Rules.link_problems
  # TURBOREL_DOC names main's doc/client/, to check each citation's heading.
  dir = ENV.fetch("TURBOREL_DOC", nil)
  problems.concat(Rules.citation_problems(dir)) if dir
  abort problems.join("\n") unless problems.empty?
end
