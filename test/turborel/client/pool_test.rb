# frozen_string_literal: true

require "test_helper"

module Turborel
  module Client
    # A pool's settings, with no server.
    class PoolTest < Minitest::Test
      include TestSupport

      # Verifies: [CLIENT Pools] a pool's settings and their defaults: at
      # most 10 made and 10 idle, idle at most ten minutes, living at most an
      # hour, waiting 30 seconds, each checked as it is handed out, no
      # statements of the program's run at reset.
      def test_pool_defaults
        assert_equal({ max: 10, max_idle: 10, idle_timeout: 600, max_lifetime: 3600, wait: 30, check: true, reset: [] },
                     PoolConfig.default.to_h)
      end
    end
  end
end
