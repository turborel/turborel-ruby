# frozen_string_literal: true

# Each group needs only those above it as it loads.
require_relative "turborel/error"
require_relative "turborel/failure"
require_relative "turborel/values"
require_relative "turborel/version"

require_relative "turborel/protocol/frame"
require_relative "turborel/protocol/reader"
require_relative "turborel/protocol/tail"
require_relative "turborel/protocol/writer"

require_relative "turborel/protocol/json_binary"
require_relative "turborel/protocol/types"
require_relative "turborel/protocol/values"

require_relative "turborel/protocol/fields"
require_relative "turborel/protocol/json_decoder"
require_relative "turborel/protocol/value_reader"
require_relative "turborel/protocol/value_writer"

require_relative "turborel/protocol/capabilities"
require_relative "turborel/protocol/compression"
require_relative "turborel/protocol/end_point"
require_relative "turborel/protocol/replies"
require_relative "turborel/protocol/requests"
require_relative "turborel/protocol/scram"

# The Ruby driver for turborel, a relational database system. It speaks
# turborel's native protocol, version 1, itself, in Ruby alone, with no
# native extension and no client library beneath it (RULES.md D1).
#
# What it offers is a plain API in the manner of the pg gem: a connection,
# its statements run with or without parameters, prepared statements,
# results and transactions; and an ActiveRecord adapter beside it, under
# its own require path (RULES.md D2). Until those are built, this module
# holds the gem's version, its error type and the protocol's codec.
module Turborel
end
