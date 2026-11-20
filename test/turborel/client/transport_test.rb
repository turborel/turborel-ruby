# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../../support/fake_server"

module Turborel
  module Client
    # Streams to a server.
    class TransportTest < Minitest::Test
      include TestSupport

      # Verifies: [CLIENT Connecting] a server that cannot be reached over
      # TCP, or at a local socket, is a connection failure (08006).
      def test_unreachable_servers_fail
        assert_fails { Transport.open(Targets.tcp("127.0.0.1", 1), 1) }
        Dir.mktmpdir do |dir|
          path = Gem.win_platform? ? "\\\\.\\pipe\\turborel-ruby-none" : File.join(dir, "none")
          assert_fails { Transport.open(Targets.local(path), 1) }
        end
      end

      # Verifies: [CLIENT Connecting] a TLS handshake that fails, as with a
      # server that speaks none, is a connection failure saying so.
      def test_failed_handshake
        server = FakeServer.new { |peer| peer.write("not TLS" * 10) }
        context = OpenSSL::SSL::SSLContext.new
        target = Targets.tls("127.0.0.1", server.port, server_name: "localhost", context:)
        error = assert_fails { Transport.open(target, 5) }

        assert_match(/TLS handshake/, error.message)
        server.join
      end

      # Verifies: [CLIENT Timeouts] a busy named pipe is tried again until
      # the connect timeout has passed, and without one, for ever.
      def test_busy_pipes_wait_the_connect_timeout
        began = Process.clock_gettime(Process::CLOCK_MONOTONIC) - 2

        assert Transport.past?(began, 1)
        refute Transport.past?(began, 5)
        refute Transport.past?(began, nil)
      end

      # Verifies: [CLIENT Timeouts] TLS is begun within the connect timeout:
      # a server that never answers the handshake loses the connection.
      def test_handshake_waits_the_connect_timeout
        server = FakeServer.new(&:rest)
        target = Targets.tls("127.0.0.1", server.port, server_name: "localhost", context: OpenSSL::SSL::SSLContext.new)
        error = assert_fails { Transport.open(target, 0.05) }

        assert_match(/in time/, error.message)
        server.join
      end
    end
  end
end
