# frozen_string_literal: true

require "socket"
require "test_helper"
require_relative "../../support/fake_server"

module Turborel
  module Client
    # Connecting by settings to one of several servers, against servers of
    # the test's own script.
    class FailoverTest < Minitest::Test
      include TestSupport

      def settings(uri) = Settings.from_uri(uri) { nil }

      # A server whose session tells SERVER_READ_ONLY +told+, or tells
      # nothing and answers the role query with +rows+, or fails it with
      # +failure+.
      def server(told: nil, rows: nil, failure: nil)
        FakeServer.new do |peer|
          peer.frame
          peer.status("SERVER_READ_ONLY", told) if told
          peer.ready
          if rows || failure
            peer.frame
            failure ? peer.error(*failure) : answer(peer, rows)
          end
          peer.frame
        end
      end

      def answer(peer, rows)
        peer.reply("D", Protocol::Writer.new.u32(1).flag(true).str("ROLE").raw("\x05\x0A\x00\x00\x00\x00".b).flag(false))
        writer = Protocol::Writer.new.u32(rows.size)
        rows.each { |row| Protocol::ValueWriter.row_values(writer, row) }
        peer.reply("B", writer)
        peer.complete
      end

      def at(server, target) = "turborel://ann@127.0.0.1:#{server.port}/?tls_mode=disable&target=#{target}"

      # Verifies: [CLIENT Several servers] the role told by SERVER_READ_ONLY:
      # read-only kept where it is asked, and read-write refused, the
      # connection left (08001).
      def test_the_role_told
        replica = server(told: "YES")
        connection = settings(at(replica, "read-only")).connect

        assert_equal :read_only, Role.of(connection)
        connection.terminate
        replica.join
        refused = server(told: "YES")
        error = assert_fails([-919, "08001"]) { settings(at(refused, "read-write")).connect }

        assert_equal "the server is read-only, and read-write is asked", error.message
      end

      # Verifies: [CLIENT Several servers] of a server that does not tell
      # it, the role read from INFORMATION_SCHEMA.REPLICAS, as its own
      # transaction: PRIMARY read-write, another read-only, no row unknown,
      # no such table a server alone, read-write.
      def test_the_role_asked
        [[[["PRIMARY  "]], :read_write], [[["REPLICA"]], :read_only], [[], :unknown]].each do |rows, role|
          fake = server(rows:)
          connection = settings(at(fake, "any")).connect
          connection.autocommit = false

          assert_equal [role, false], [Role.of(connection), connection.autocommit]
          connection.terminate
          fake.join
        end
        alone = server(failure: [-103, "2A000", "no such table"])

        assert_equal "read-write", Role::WORDS.fetch(:read_write)
        connection = settings(at(alone, "read-write")).connect
        connection.terminate
        failing = server(failure: [-919, "08006", "gone"])
        assert_fails { settings(at(failing, "read-only")).connect }
      end

      # Verifies: [CLIENT Several servers] a server that cannot be reached
      # passed for the next; with none kept, a failure naming each address
      # and why (08001), 28000 if the last refused the user; of one server,
      # its own failure.
      def test_none_kept
        listener = TCPServer.new("127.0.0.1", 0)
        dead = listener.addr[1]
        listener.close
        live = server(told: "NO")
        connection = settings("turborel://ann@127.0.0.1:#{dead},127.0.0.1:#{live.port}/?tls_mode=disable").connect

        assert_equal "ANN", connection.authorization
        connection.terminate
        live.join
        both = assert_fails([-919, "08001"]) do
          settings("turborel://ann@127.0.0.1:#{dead},127.0.0.1:#{dead}/?tls_mode=disable").connect
        end

        assert_match(/\Ano server was kept: 127\.0\.0\.1 \(127\.0\.0\.1:#{dead}\): cannot connect: .*; 127\.0\.0\.1/,
                     both.message)
        assert_equal "08006", assert_fails {
          settings("turborel://ann@127.0.0.1:#{dead}/?tls_mode=disable").connect
        }.sqlstate
        refused = Failure.new(sqlcode: -919, sqlstate: "28000", message: "no", rule: nil, position: nil, active: false,
                              diagnostics: nil)

        assert_equal "28000", Settings.none_kept([["a", both.failure], ["b", refused]]).sqlstate
        assert_equal(["08001", "no server is named"], Settings.none_kept([]).then { [_1.sqlstate, _1.message] })
      end

      # Verifies: [CLIENT TLS by mode] prefer: TLS if the server takes it,
      # else plain TCP, connecting again after a failed handshake.
      def test_prefer_connects_again_over_plain_tcp
        listener = TCPServer.new("127.0.0.1", 0)
        thread = Thread.new do
          Thread.current.report_on_exception = false
          listener.accept.close
          socket = listener.accept
          peer = FakeServer::Peer.new(socket)
          peer.frame
          peer.ready
          peer.frame
        ensure
          socket&.close
          listener.close
        end
        connection = settings("turborel://ann@127.0.0.1:#{listener.addr[1]}/").connect

        assert_equal :tcp, connection.target.kind
        connection.terminate
        thread.join
      end

      # Verifies: [CLIENT TLS by mode] each mode's TLS: none of disable; of
      # prefer and require no certificate checked; of verify-ca and
      # verify-full the authorities trusted, the name checked of
      # verify-full alone; a client certificate needing its key.
      def test_tls_by_mode
        files = TlsFiles.new(roots: nil, system_roots: true, certificate: nil, key: nil, server_name: nil)

        assert_nil TLS.of_mode(:disable, files)
        assert_equal OpenSSL::SSL::VERIFY_NONE, TLS.of_mode(:require, files).verify_mode
        assert_equal([OpenSSL::SSL::VERIFY_PEER, false],
                     TLS.of_mode(:verify_ca, files).then { [_1.verify_mode, _1.verify_hostname] })
        assert TLS.of_mode(:verify_full, files).verify_hostname
        assert_fails { TLS.of_mode(:verify_full, files.with(system_roots: false)) }
        assert_fails { TLS.of_mode(:prefer, files.with(certificate: "/no/cert.pem")) }
        assert_fails { TLS.of_mode(:prefer, files.with(certificate: "/no/cert.pem", key: "/no/key.pem")) }
      end

      # Verifies: [CLIENT TLS by mode] channel_binding require refuses,
      # before anything is proved, settings whose mechanism binds nothing or
      # a connection not over TLS (28000); a password over plain TCP refused
      # before it is sent.
      def test_channel_binding_required
        fake = FakeServer.new(&:rest)
        assert_fails([-919, "28000"]) do
          settings("turborel://ann@127.0.0.1:#{fake.port}/?tls_mode=disable&channel_binding=require").connect
        end
        fake.join
        other = FakeServer.new(&:rest)
        assert_fails([-919, "28000"]) do
          settings("turborel://ann:pw@127.0.0.1:#{other.port}/?tls_mode=disable").connect
        end
        other.join
      end

      # Verifies: [CLIENT Several servers] hosts tried in a random order for
      # each connection with load_balance=random, each once.
      def test_random_order
        first = server(told: "NO")
        second = server(told: "NO")
        uri = "turborel://ann@127.0.0.1:#{first.port},127.0.0.1:#{second.port}/?tls_mode=disable&load_balance=random"
        connection = settings(uri).connect

        assert_includes [first.port, second.port], connection.target.port
        connection.terminate
        used, unused = connection.target.port == first.port ? [first, second] : [second, first]
        used.join
        unused.instance_variable_get(:@listener).close
        assert_raises(IOError) { unused.join }
      end
    end
  end
end
