# frozen_string_literal: true

require "test_helper"

# The gem's root module.
class TurborelTest < Minitest::Test
  # Verifies: [DESIGN] D1 requiring the gem loads the codec, with no I/O.
  def test_requiring_the_gem_loads_the_codec
    assert_kind_of Module, Turborel::Protocol::Requests
    assert_equal "\x47\x00\x00\x00\x00".b, Turborel::Protocol::Requests.ping
  end
end
