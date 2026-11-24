# frozen_string_literal: true

require "test_helper"

module Turborel
  module Protocol
    # The capabilities of version 1.
    class CapabilitiesTest < Minitest::Test
      # Verifies: [PROTOCOL Capabilities] the twenty capabilities, in the
      # table's order, parameter-modes last; names this side does not know
      # left out.
      def test_capabilities_in_order
        assert_equal 20, Capabilities::ALL.size
        assert_equal %w[notices parameter-modes], [Capabilities::ALL.first, Capabilities::ALL.last]
        assert_equal %w[notices compression], Capabilities.known(%w[compression nope notices])
      end
    end
  end
end
