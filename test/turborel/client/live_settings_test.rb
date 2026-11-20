# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../../server/live_server"

module Turborel
  module Client
    # Connections by settings to a live server (RULES.md R-TEST-8), skipped
    # without one.
    class LiveSettingsTest < Minitest::Test
      include TestSupport
      include LiveServer::Case

      # The password of +user+, percent-encoded for a URI.
      def secret(user) = LiveServer::USERS.fetch(user).gsub("'", "%27").gsub(" ", "%20")

      # Connects as the settings of +uri+ say, the environment empty, and
      # gives the block the connection, terminated after.
      def by(uri)
        connection = Settings.from_uri(uri) { nil }.connect
        yield connection
      ensure
        connection&.terminate unless connection&.lost?
      end

      def base = "127.0.0.1:#{server.port}"

      # Verifies: [CLIENT Connecting by settings] a connection as settings
      # say: by trust with no password, over plain TCP under disable and
      # over TLS under prefer; a password proved by SCRAM over TLS; a
      # secret mechanism over plain TCP refused before anything is sent.
      def test_connections_by_settings
        by("turborel://ann@#{base}/?tls_mode=disable") do |c|
          assert_equal [:tcp, "ANN"], [c.target.kind, c.authorization]
        end
        by("turborel://ann@#{base}/") { |c| assert_equal :tls, c.target.kind }
        by("turborel://bob:#{secret("bob")}@#{base}/?tls_mode=require") { |c| assert_equal "BOB", c.authorization }
        assert_fails([-919, "28000"]) { by("turborel://bob:#{secret("bob")}@#{base}/?tls_mode=disable") { nil } }
      end

      # Verifies: [CLIENT TLS by mode] verify-full against server_name, else
      # the host's; verify-ca of any name; require unchecked; a verifying
      # mode with no authority trusted refused; channel binding required
      # met by SCRAM over TLS, refused of trust.
      def test_tls_modes
        roots = "tls_roots=#{server.ca}"

        by("turborel://ann:#{secret("ann")}@localhost:#{server.port}/?tls_mode=verify-full&#{roots}") do |c|
          assert_equal :tls, c.target.kind
        end
        by("turborel://ann@#{base}/?tls_mode=verify-full&#{roots}&server_name=localhost") do |c|
          assert c.granted?("ping")
        end
        by("turborel://ann@#{base}/?tls_mode=verify-ca&#{roots}&server_name=wrong") { |c| assert c.granted?("ping") }
        assert_fails { by("turborel://ann@#{base}/?tls_mode=verify-full&#{roots}&server_name=wrong") { nil } }
        assert_fails { by("turborel://ann@#{base}/?tls_mode=verify-full") { nil } }
        by("turborel://ann:#{secret("ann")}@#{base}/?tls_mode=require&channel_binding=require") do |c|
          assert_equal "ANN", c.authorization
        end
        assert_fails([-919, "28000"]) { by("turborel://ann@#{base}/?channel_binding=require") { nil } }
      end

      # Verifies: [CLIENT Several servers] a server that cannot be reached
      # passed for the next; target read-write keeping a server alone,
      # read-only refusing it (08001); the role its session sees.
      def test_several_servers_and_roles
        by("turborel://ann@127.0.0.1:1,#{base}/?target=read-write&connect_timeout=5") do |c|
          assert_equal :read_write, Role.of(c)
        end
        refused = assert_fails([-919, "08001"]) { by("turborel://ann@#{base}/?target=read-only") { nil } }

        assert_equal "the server is read-write, and read-only is asked", refused.message
      end

      # Verifies: [CLIENT Connecting by settings] a local socket by its path,
      # percent-encoded, no TLS over it; application_name sent as the
      # connection attribute application.
      def test_local_socket_and_application_name
        path = server.socket.gsub("/", "%2F").gsub("\\", "%5C")
        query = "SELECT ATTRIBUTE_VALUE FROM INFORMATION_SCHEMA.CONNECTION_ATTRIBUTES " \
                "WHERE ATTRIBUTE_NAME = 'application'"
        uri = "turborel://ann@#{path}/?application_name=settings%20test&tls_mode=verify-full&tls_roots=#{server.ca}"
        by(uri) do |c|
          assert_equal :local, c.target.kind
          assert_equal [["settings test"]], c.query(query).rows
        end
      end

      # Verifies: [CLIENT The password file] a password the settings do not
      # give found in the password file, by host, port and user; [CLIENT
      # The service file] a service named giving the rest.
      def test_password_and_service_files
        Dir.mktmpdir("turborel-ruby-files") do |dir|
          passfile = File.join(dir, "pass")
          File.write(passfile, "127.0.0.1:#{server.port}:bob:#{LiveServer::USERS["bob"].gsub(":", "\\:")}\n")
          services = File.join(dir, "services")
          File.write(services, "[live]\nhost = #{base}\nuser = bob\ntls_mode = require\npassfile = #{passfile}\n")
          settings = Settings.resolve(Options.new("service" => "live", "service_file" => services)) { nil }
          connection = settings.connect

          assert_equal "BOB", connection.authorization
          connection.terminate
        end
      end

      # Verifies: [CLIENT The SCRAM key cache] one cache for every
      # connection the same settings make: the second login of a password
      # takes the keys the first derived.
      def test_one_key_cache_for_the_settings
        settings = Settings.from_uri("turborel://bob:#{secret("bob")}@#{base}/?tls_mode=require") { nil }
        2.times { settings.connect.terminate }

        assert_equal [1, 1], settings.key_cache.lookups
      end
    end
  end
end
