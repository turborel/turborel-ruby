# Installing

[Contents](README.md)

This chapter will tell what the driver needs, Ruby 3.3 or later on Linux,
macOS or Windows, and how a program takes the gem `turborel` in from
RubyGems. No package is published until every Turborel driver is
done; until then the driver is built from its source, as the
repository's
[README](../../README.md)
says. The chapter is written with the standard API, at milestone M7, and
again when the packages are published.

Until then, a program builds the gem from a clone of the repository:

```
git clone https://github.com/turborel/turborel-ruby.git
cd turborel-ruby
bundle config set --local path vendor/bundle
bundle install
bundle exec rake build
gem install pkg/turborel-0.0.0.gem
```

or names the clone in its Gemfile, as `gem "turborel", path: "../turborel-ruby"`.
