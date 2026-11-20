# frozen_string_literal: true

require "test_helper"

module Turborel
  module Client
    # Targets and timeouts.
    class TargetTest < Minitest::Test
      # Verifies: [CLIENT Connecting] a target is TCP, at port 7422 unless
      # told another, a local socket, or TLS of a name and a context.
      def test_targets
        assert_equal [:tcp, "db", 7422], Targets.tcp("db").deconstruct.first(3)
        assert_equal [:local, "/run/s"], [Targets.local("/run/s").kind, Targets.local("/run/s").path]
        tls = Targets.tls("db", 1, server_name: "n", context: nil)

        assert_equal [:tls, "n"], [tls.kind, tls.server_name]
        assert_equal "\\\\.\\pipe\\turborel", DEFAULT_PIPE
      end

      # Verifies: [CLIENT Timeouts] connecting and each step of the login
      # wait 30 seconds by default, each read and write after no limit;
      # terminate waits 60 seconds at most, a cancel 10.
      def test_default_timeouts
        assert_equal Timeouts.new(connect: 30, read: nil), DEFAULT_TIMEOUTS
        assert_equal [60, 10], [TERMINATE_WITHIN, CANCEL_WITHIN]
      end
    end
  end
end
