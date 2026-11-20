# frozen_string_literal: true

require_relative "turborel/error"
require_relative "turborel/protocol/frame"
require_relative "turborel/version"

# The Ruby driver for turborel, a relational database system. It speaks
# turborel's native protocol, version 1, itself, in Ruby alone, with no
# native extension and no client library beneath it (RULES.md D1).
#
# What it offers is a plain API in the manner of the pg gem: a connection,
# its statements run with or without parameters, prepared statements,
# results and transactions; and an ActiveRecord adapter beside it, under
# its own require path (RULES.md D2). Until those are built, this module
# holds the gem's version, its error type and the protocol's frame header.
module Turborel
end
