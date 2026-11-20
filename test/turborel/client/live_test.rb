# frozen_string_literal: true

require "test_helper"
require_relative "../../server/live_server"

module Turborel
  module Client
    # Connections to a live server (RULES.md R-TEST-8), skipped without one.
    class LiveTest < Minitest::Test
      include TestSupport
      include LiveServer::Case

      def tls_target(context = TLS.context(roots: server.ca))
        Targets.tls("127.0.0.1", server.port, server_name: "localhost", context:)
      end

      # Verifies: [PROTOCOL The Native Protocol] a client reaches the server
      # over TCP at its port, and asking for no capability sees the first
      # form: none granted, no Status.
      def test_tcp_and_the_first_form
        connect(tcp, Trust.new) { |c| assert_equal "ANN", c.authorization }
        connect(tcp, Trust.new, offer: Offers.none) do |c|
          assert_empty c.granted
          assert_empty c.settings
        end
      end

      # Verifies: [PROTOCOL Mechanisms] trust is accepted at once, from a
      # client on the server's machine, as the user it names.
      def test_trust
        connect(tcp, Trust.new) do |c|
          assert_equal "turborel 0.0.0 (alpha)", c.server
          assert_equal Protocol::Capabilities::ALL - [Protocol::Capabilities::COMPRESSION], c.granted
        end
      end

      # Verifies: [CLIENT Connecting] the server's product and the session's
      # authorization identifier, as Ready told them, over TCP by trust.
      def test_connect_over_tcp
        connection = Client.connect("127.0.0.1", server.port, user: "bob", mechanism: Trust.new)

        assert_equal ["BOB", "turborel 0.0.0 (alpha)"], [connection.authorization, connection.server]
        connection.terminate

        assert_predicate connection, :lost?
      end

      # Verifies: [CLIENT Connecting] SCRAM-SHA-256 of a password, over a
      # Unix socket or a named pipe; a wrong password refused (28000).
      def test_scram_over_a_local_socket
        connection = Client.connect_local(server.socket, user: "ann", mechanism: Scram.new(LiveServer::USERS["ann"]))

        assert_equal "ANN", connection.authorization
        connection.terminate
        wrong = assert_fails([-919, "28000"]) do
          Client.connect_local(server.socket, user: "ann", mechanism: Scram.new("no"))
        end
        assert_match(/password is wrong/, wrong.message)
      end

      # Verifies: [PROTOCOL Mechanisms] password sends the password's UTF-8,
      # taken over a Unix socket or a named pipe.
      def test_password_over_a_local_socket
        connection = Client.connect_local(server.socket, user: "bob", mechanism: Password.new(LiveServer::USERS["bob"]))

        assert_equal "BOB", connection.authorization
        connection.terminate
      end

      # Verifies: [PROTOCOL Mechanisms] scram-sha-256-plus is bound by
      # tls-exporter over TLS 1.3, and by tls-server-end-point over TLS 1.2,
      # the server checking the binding.
      def test_scram_plus_over_tls
        mechanism = Scram.new(LiveServer::USERS["ann"], binding: :require)

        connect(tls_target, mechanism) { |c| assert_equal "ANN", c.authorization }
        old = TLS.context(roots: server.ca).tap { |context| context.max_version = OpenSSL::SSL::TLS1_2_VERSION }
        older = Scram.new(LiveServer::USERS["ann"], binding: :require)

        connect(tls_target(old), older) { |c| assert_equal "ANN", c.authorization }
        assert_equal(%i[exporter end_point], [mechanism, older].map { _1.instance_variable_get(:@exchange).binding })
      end

      # Verifies: [CLIENT Connecting] SCRAM-SHA-256-PLUS over TLS, by
      # tls-exporter over TLS 1.3 and by the server's certificate over TLS
      # 1.2; the server proves it knows the verifier.
      def test_scram_plus_names_its_binding
        mechanism = Scram.new(LiveServer::USERS["ann"])
        channel = Transport.open(tls_target, 5).then { |stream, bound| bound.tap { stream.close } }
        mechanism.bind(channel)

        assert_equal Protocol::Scram::MECHANISM_PLUS, mechanism.name
        refute_nil channel.exporter
        connect(tls_target, Scram.new(LiveServer::USERS["ann"])) { |c| assert_equal "ANN", c.authorization }
      end

      # Verifies: [PROTOCOL Mechanisms] certificate proves the user its TLS
      # client certificate's common name names.
      def test_certificate
        context = TLS.context(roots: server.ca, certificate: server.client_certificate, key: server.client_key)

        connect(tls_target(context), Certificate.new) { |c| assert_equal "ANN", c.authorization }
      end

      # Verifies: [CLIENT Connecting] certificate: TLS trusting a PEM file
      # of authorities, presenting a certificate chain and key from two more;
      # a server not trusted fails the handshake (08006).
      def test_tls_trusts_the_files_given
        context = TLS.context(roots: server.ca, certificate: server.client_certificate, key: server.client_key)

        connect(tls_target(context), Certificate.new) { |c| assert_equal "ANN", c.authorization }
        stranger = File.join(server.dir, "client.pem")
        assert_fails { Client.connect_to(tls_target(TLS.context(roots: stranger)), user: "ann", mechanism: Trust.new) }
      end

      # Verifies: [CLIENT Connecting] a TLS stream the program opened, bound
      # by the program before SCRAM-SHA-256-PLUS.
      def test_a_stream_of_the_programs_own
        stream, channel = Transport.open(tls_target, 5)
        mechanism = Scram.new(LiveServer::USERS["ann"], binding: :require)
        mechanism.bind(channel)
        connection = Connection.open(stream.io, user: "ann", mechanism:)

        assert_equal "ANN", connection.authorization
        connection.terminate
      end

      # Verifies: [CLIENT Connecting] TLS trusting the platform's
      # authorities, which SSL_CERT_FILE names instead where it is set.
      def test_platform_authorities_and_ssl_cert_file
        before = ENV.fetch("SSL_CERT_FILE", nil)
        ENV["SSL_CERT_FILE"] = server.ca
        context = TLS.context(platform: true)

        connect(tls_target(context), Trust.new) { |c| assert_equal "ANN", c.authorization }
      ensure
        ENV["SSL_CERT_FILE"] = before
      end

      # Verifies: [PROTOCOL Opening a connection] a user name not an
      # identifier, or a mechanism the server does not serve, is refused
      # before any exchange (28000); a version other than 1 is refused
      # (08004).
      def test_refusals_of_hello
        unserved = Class.new(Mechanism) { define_method(:name) { "nope" } }.new
        assert_fails([-919, "28000"]) { Client.connect_to(tcp, user: "ann", mechanism: unserved) }
        assert_fails([-919, "28000"]) { Client.connect_to(tcp, user: "1 x", mechanism: Trust.new) }
        assert_equal "08004", hello_of_version(2).failure.sqlstate
      end

      def hello_of_version(version)
        stream, = Transport.open(tcp, 5)
        body = Protocol::Writer.new.u32(version).str("ann").str("trust").bytes("").strs([]).to_s
        stream.write_all(Protocol::Frame.encode(Protocol::Requests::HELLO, body))
        kind, length = Protocol::Frame.decode_header(stream.read_exactly(5))
        Protocol::Replies.decode(kind, stream.read_exactly(length)).tap { stream.close }
      end

      # Verifies: [PROTOCOL Status 'T'] at login the server tells
      # AUTHORIZATION, SCHEMA, READ_ONLY, SERVER_VERSION, SERVER_READ_ONLY,
      # CATALOG and OWNER, and every setting a session may set, among them
      # SESSION.TIME_ZONE and TRANSACTION.ISOLATION.
      def test_statuses_at_login
        connect(tcp, Trust.new) do |c|
          told = %w[AUTHORIZATION SCHEMA READ_ONLY SERVER_READ_ONLY OWNER].map { |name| c.setting(name) }

          assert_equal %w[ANN ANN NO NO YES], told
          assert_match(/\Aturborel /, c.setting("SERVER_VERSION"))
          refute_nil c.setting("CATALOG")
          assert(%w[SESSION.TIME_ZONE TRANSACTION.ISOLATION].all? { |name| c.settings.key?(name) })
        end
      end

      # Verifies: [PROTOCOL Capabilities] compression granted where asked
      # for, then replies inflated and requests compressed past the
      # threshold, Ready never compressed.
      def test_compression
        connect(tcp, Trust.new, offer: Offers.compressed(Offers.default)) do |c|
          assert c.granted?(Protocol::Capabilities::COMPRESSION)
          long = "y" * 5000
          sent = []
          counting = Module.new do
            define_method(:write_all) do |bytes|
              sent << bytes.getbyte(0)
              super(bytes)
            end
          end
          c.instance_variable_get(:@stream).singleton_class.prepend(counting)

          assert_equal [[long]], c.query("VALUES '#{long}'").rows
          assert_equal ["z".ord], sent.uniq
        end
      end

      # Verifies: [PROTOCOL Cancel 'Z'] Cancel is the first and only message
      # of a connection of its own, which the server closes with no reply.
      def test_cancel_closes_with_no_reply
        connect(tcp, Trust.new) do |c|
          c.canceller.cancel

          refute_predicate c, :lost?
        end
      end

      # Verifies: [PROTOCOL Terminate 'X'] Terminate ends the session, and
      # the server closes the connection.
      def test_terminate
        connection = Client.connect_to(tcp, user: "ann", mechanism: Trust.new)

        assert_nil connection.terminate
        assert_predicate connection, :lost?
      end
    end
  end
end
