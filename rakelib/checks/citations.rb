# frozen_string_literal: true

module Checks
  # Every citation names a heading, decision or rule that exists (RULES.md
  # D6, R-TRACE-2): a heading of Turborel's documents, kept in
  # rakelib/headings/ as at the commit CONFORMANCE.md names, or a decision
  # or rule of RULES.md.
  module Citations
    # The headings of each book a citation names.
    BOOKS = { "PROTOCOL" => "rakelib/headings/protocol.txt", "CLIENT" => "rakelib/headings/client.txt" }.freeze
    # A citation of a heading; one whose heading begins with `<` or is
    # `...` stands for any, as the documents write it.
    HEADING = /\[(PROTOCOL|CLIENT) ([^\]<.][^\]]*)\]/
    # A citation of a decision.
    DECISION = /(?:\[DESIGN\]|(?<![Tt]urborel's )(?<![Tt]urborel )RULES\.md) D(\d+)\b/
    # A rule's ID.
    RULE = /\bR-[A-Z]+-\d+\b/
    # The files citations are checked in: the sources, and the documents.
    DOCUMENTS = ["*.md", "doc/**/*.md", ".github/**/*.md", ".github/**/*.yml", ".rubocop.yml", ".simplecov",
                 ".githooks/*"].freeze

    # @return [Array<String>] every citation that names nothing
    def self.problems
      known = { headings: headings, decisions: decisions, rules: rules }
      (Sources.files + Dir.glob(DOCUMENTS)).uniq.flat_map { |path| file_problems(path, joined(File.read(path)), known) }
    end

    # @return [String] +text+ with its lines joined, a comment's markers
    #   between them dropped, so a citation wrapped across lines is read
    #   whole
    def self.joined(text) = text.gsub(/[ \t]*\n[ \t]*(?:#[ \t]*)?/, " ")

    # @return [Array<String>] the citations of one file that name nothing
    def self.file_problems(path, text, known)
      heading_problems(path, text, known[:headings]) +
        missing(path, text.scan(DECISION).flatten.map { |number| "D#{number}" }, known[:decisions], "decision") +
        missing(path, text.scan(RULE), known[:rules], "rule")
    end

    # @return [Array<String>] the headings cited in +text+ that no book has
    def self.heading_problems(path, text, headings)
      text.scan(HEADING).filter_map do |book, heading|
        unless headings.fetch(book).include?(heading)
          "#{path}: [#{book} #{heading}] is no heading of Turborel's documents"
        end
      end
    end

    # @return [Array<String>] the IDs +cited+ that are not +known+
    def self.missing(path, cited, known, what)
      (cited - known).map { |id| "#{path}: #{id} is no #{what} of RULES.md" }
    end

    # @return [Hash{String => Array<String>}] each book's headings
    def self.headings
      BOOKS.transform_values { |path| File.readlines(path, chomp: true).reject { |line| line.start_with?("#") } }
    end

    # @return [Array<String>] the numbers of RULES.md's decisions
    def self.decisions = File.read("RULES.md").scan(/^#### (D\d+)\./).flatten

    # @return [Array<String>] the IDs of RULES.md's rules
    def self.rules = File.read("RULES.md").scan(/^\| (R-[A-Z]+-\d+) \|/).flatten
  end
end
