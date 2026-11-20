# frozen_string_literal: true

module Checks
  # The manual's layout, which turborel.com's documentation site reads,
  # and every relative link of the documents (RULES.md R-DOC-7): each page
  # opens with its `# Title`; a chapter's next line holds only
  # `[Contents](README.md)`; each volume's README.md links the set and
  # lists its pages; every relative link resolves, a link from doc/ to
  # the repository's own files too, which the site points at GitHub; and
  # doc/ holds no image.
  module Manual
    # The documents whose relative links must resolve.
    DOCUMENTS = ["*.md", "doc/**/*.md", ".github/**/*.md"].freeze
    # A Markdown link's target.
    LINK = /\]\(([^)\s]+)\)/
    # A target that is a URL or an anchor, not a file.
    EXTERNAL = /\A(?:[a-z]+:|#)/
    # A chapter's line after its title.
    CONTENTS = "[Contents](README.md)"
    # A volume's line back to the set.
    SET = "[The documentation set](../README.md)"
    # An image, in Markdown or HTML.
    IMAGE = /!\[|<img\b/i

    # @return [Array<String>] every problem of the manual and the links
    def self.problems
      Dir.glob(DOCUMENTS).flat_map { |path| links(path) } + Dir.glob("doc/**/*.md").flat_map { |path| page(path) } +
        Dir.glob("doc/*/README.md").flat_map { |path| volume(path) } + images
    end

    # @return [Array<String>] relative links of +path+ that resolve to no
    #   file
    def self.links(path)
      File.read(path).scan(LINK).flatten.filter_map do |target|
        next if target.match?(EXTERNAL)

        file = File.expand_path(target.sub(/#.*/, ""), File.dirname(path))
        "#{path}: the link #{target} resolves to no file" unless File.exist?(file)
      end
    end

    # @return [Array<String>] images in doc/: a file not of Markdown, or an
    #   image in a page
    def self.images
      others = Dir.glob("doc/**/*").reject { |path| File.directory?(path) || path.end_with?(".md") }
      others.map { |path| "#{path}: doc/ holds Markdown pages alone, no image" } +
        Dir.glob("doc/**/*.md").select { |path| File.read(path).match?(IMAGE) }.map { |path| "#{path}: holds an image" }
    end

    # @return [Array<String>] a page without its title, or a chapter
    #   without its contents line
    def self.page(path)
      lines = File.readlines(path, chomp: true)
      found = []
      found << "#{path}: does not open with its `# Title`" unless lines.first&.start_with?("# ")
      chapter = File.basename(path) != "README.md"
      found << "#{path}: its third line is not #{CONTENTS}" if chapter && lines[2] != CONTENTS
      found
    end

    # @return [Array<String>] a volume's README.md that does not link the
    #   set or list each of its pages
    def self.volume(path)
      text = File.read(path)
      found = text.include?(SET) ? [] : ["#{path}: does not link #{SET}"]
      pages = Dir.glob(File.join(File.dirname(path), "*.md")).map { |page| File.basename(page) } - ["README.md"]
      found + pages.reject { |page| text.include?("(#{page})") }.map { |page| "#{path}: does not list #{page}" }
    end
  end
end
