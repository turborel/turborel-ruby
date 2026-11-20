# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# The development tools (RULES.md D10), never needed at run time.
group :development do
  # The ActiveRecord adapter's tests (RULES.md D2); never a dependency of
  # the gem.
  gem "activerecord", ">= 8.1"
  gem "minitest", ">= 5.20"
  gem "rake", ">= 13.1"
  gem "rbs", ">= 3.4"
  gem "rubocop", ">= 1.81"
  gem "rubocop-minitest", ">= 0.38"
  gem "rubocop-performance", ">= 1.26"
  gem "rubocop-rake", ">= 0.7"
  gem "simplecov", ">= 0.22"
  gem "steep", ">= 2.0"
  gem "yard", ">= 0.9.37"
end
