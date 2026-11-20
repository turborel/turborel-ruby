# frozen_string_literal: true

require_relative "lib/turborel/version"

Gem::Specification.new do |spec|
  spec.name = "turborel"
  # The turborel release the driver is made for, the same number as the
  # server's; the alpha, 0.0.0, speaks protocol version 1 (RULES.md D5).
  spec.version = Turborel::VERSION
  spec.authors = ["Turborel Inc."]
  spec.email = ["hello@turborel.com"]

  spec.summary = "The Ruby driver for turborel, over its native protocol."
  spec.description = <<~TEXT
    The Ruby driver for turborel. It speaks turborel's native protocol,
    version 1, in Ruby alone, and is built to match turborel-client, with a
    plain API of connections, results and prepared statements and an
    ActiveRecord adapter. Its
    version is the turborel release it is made for.
  TEXT
  spec.homepage = "https://github.com/turborel/turborel-ruby"
  spec.license = "BSD-2-Clause-Patent"
  spec.required_ruby_version = ">= 3.3"

  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "changelog_uri" => "#{spec.homepage}/commits/main",
    "documentation_uri" => "https://turborel.com/docs/drivers/ruby/",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb", "sig/**/*.rbs", "LICENSE", "README.md", "TRADEMARK.md"]
  spec.require_paths = ["lib"]

  # RULES.md D9: bigdecimal is a bundled gem from Ruby 3.4, no longer a
  # default one, so it must be declared to be required under Bundler.
  spec.add_dependency "bigdecimal", ">= 3.1", "< 5"
end
