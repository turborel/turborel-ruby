# frozen_string_literal: true

# The project's checks, each a task, and `verify`, every check a change
# must pass (RULES.md R-PROC-1). Tasks are Ruby, never shell scripts
# (R-PROC-5), so each runs alike on Linux, macOS and Windows.

require "open3"
require "rubocop/rake_task"

# The most lines of a failed run's output told as an annotation.
ANNOTATED_LINES = 40

desc "Run the tests, with Ruby's warnings on (R-TEST-1, R-LINT-1)"
task :test do
  # A process of its own, its arguments given as a list, so no shell reads
  # them on any platform; test_helper.rb makes a warning about lib/ fail
  # its test.
  files = Dir.glob("test/**/*_test.rb")
  script = "ARGV.each { |file| require File.expand_path(file) }"
  output, status = Open3.capture2e(Gem.ruby, "-w", "-Ilib", "-Itest", "-rminitest/autorun", "-e", script, *files)
  $stdout.write(output)
  next if status.success?

  # A job's log is not public on GitHub's runners, its annotations are.
  tail = output.lines.last(ANNOTATED_LINES).join.gsub("%", "%25").gsub(/\r?\n/, "%0A")
  puts "::error title=tests on #{RUBY_PLATFORM} #{RUBY_VERSION}::#{tail}" if ENV.fetch("GITHUB_ACTIONS", nil)
  abort "the tests failed"
end

# Lint and format, in one (R-STYLE-1, R-LINT-1).
RuboCop::RakeTask.new(:rubocop)

desc "Type-check lib/ against sig/ with Steep, strictly (D11)"
task :steep do
  require "steep"
  require "steep/cli"
  status = Steep::CLI.new(argv: ["check"], stdout: $stdout, stderr: $stderr, stdin: $stdin).run
  abort "steep found type errors" unless status.zero?
end

desc "Validate the RBS signatures in sig/ (D11)"
task :rbs do
  require "rbs"
  require "rbs/cli"
  status = RBS::CLI.new(stdout: $stdout, stderr: $stderr).run(%w[-r bigdecimal -r zlib -I sig validate])
  abort "rbs found invalid signatures" unless status.nil? || status.zero?
end

desc "Run the tests under SimpleCov, failing below its floors (R-COV)"
task :coverage do
  ENV["COVERAGE"] = "1"
  Rake::Task[:test].invoke
end

desc "Every check a change must pass (R-PROC-1)"
task verify: %i[rubocop rules steep rbs doc test]

desc "Build the gem into pkg/, publishing nothing (VERSIONING.md)"
task :build do
  require "fileutils"
  require "rubygems/package"
  spec = Gem::Specification.load("turborel.gemspec")
  FileUtils.mkdir_p("pkg")
  file = Gem::Package.build(spec)
  FileUtils.mv(file, File.join("pkg", file))
  puts "pkg/#{file}"
end

desc "Run `rake verify` before every commit, from .githooks/ (D4)"
task :install_hooks do
  sh "git", "config", "core.hooksPath", ".githooks"
end

task default: :verify
