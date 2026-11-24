# frozen_string_literal: true

require "test_helper"

module Turborel
  module Protocol
    # The capabilities of version 1.
    class CapabilitiesTest < Minitest::Test
      # Verifies: [PROTOCOL Capabilities] the twenty-one capabilities, in
      # the table's order, debugger last; names this side does not know
      # left out.
      def test_capabilities_in_order
        assert_equal 21, Capabilities::ALL.size
        assert_equal %w[notices debugger], [Capabilities::ALL.first, Capabilities::ALL.last]
        assert_equal %w[notices compression], Capabilities.known(%w[compression nope notices])
      end
    end
  end
end
