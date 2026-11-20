# frozen_string_literal: true

# The API reference by YARD, which must build without a warning and leave
# no public item undocumented (RULES.md R-DOC-1, R-DOC-3).

desc "Build the API reference with YARD, failing on a warning or an undocumented item"
task :doc do
  require "yard"
  YARD::CLI::Yardoc.run("--fail-on-warning", "--no-progress", "--quiet")
  undocumented = YARD::Registry.all.select { |object| object.docstring.blank? && !object.is_a?(YARD::CodeObjects::Proxy) }
  abort "undocumented: #{undocumented.map(&:path).join(", ")}" unless undocumented.empty?
end
