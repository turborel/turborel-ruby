# frozen_string_literal: true

require "test_helper"

module Turborel
  module Protocol
    # The client's side of a SCRAM exchange.
    class ScramTest < Minitest::Test
      include TestSupport

      # RFC 7677 §3's example: its user, password and messages.
      CLIENT_NONCE = "rOprNGfwEbeRWgbNEkqO"
      # (see CLIENT_NONCE)
      BOTH = "rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0"
      # (see CLIENT_NONCE)
      SERVER_FIRST = "r=#{BOTH},s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096".freeze
      # (see CLIENT_NONCE)
      CLIENT_FINAL = "c=biws,r=#{BOTH},p=dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ=".freeze
      # (see CLIENT_NONCE)
      SERVER_FINAL = "v=6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4="

      def refused = [Error::CONNECTION_FAILURE_SQLCODE, Error::INVALID_AUTHORIZATION_SQLSTATE]

      def exchanged
        exchange = Scram.new("user")
        exchange.first(CLIENT_NONCE)
        first = exchange.read(SERVER_FIRST)
        [exchange, exchange.prove(first, Scram.derived("pencil", first.salt, first.iterations))]
      end

      # Verifies: [PROTOCOL Mechanisms] scram-sha-256's messages are RFC
      # 5802's and RFC 7677's, as its test vector gives them: client-first,
      # client-final answering server-first, server-final checked.
      def test_rfc7677_test_vector
        assert_equal "n,,n=user,r=#{CLIENT_NONCE}", Scram.new("user").first(CLIENT_NONCE)
        exchange, final = exchanged

        assert_equal CLIENT_FINAL, final
        refute_predicate exchange, :verified?
        exchange.verify(SERVER_FINAL)

        assert_predicate exchange, :verified?
      end

      # Verifies: [PROTOCOL Mechanisms] the server's signature is checked
      # before the last, empty Answer: a wrong one, or an error, refused
      # (28000).
      def test_server_signature_is_checked
        assert_fails(refused) { exchanged.first.verify("v=#{Scram.encode("\x00" * 32)}") }
        assert_fails(refused) { exchanged.first.verify("e=invalid-proof") }
        assert_fails(refused) { exchanged.first.verify("v=!!") }
        assert_fails(refused) { Scram.new.verify(SERVER_FINAL) }
      end

      # Verifies: [PROTOCOL Mechanisms] server-first must extend the client's
      # nonce, carry a salt in base 64 and positive iterations, and nothing
      # more.
      def test_server_first_is_checked
        exchange = Scram.new("user")
        assert_fails(refused) { exchange.read(SERVER_FIRST) }
        exchange.first(CLIENT_NONCE)

        n = CLIENT_NONCE

        ["r=other,s=QQ==,i=1", "r=#{n},s=QQ==,i=1", "r=#{n}x,s=*,i=1", "r=#{n}x,s=QQ==,i=0",
         "r=#{CLIENT_NONCE}x,s=QQ==,i=4294967296", "r=#{CLIENT_NONCE}x,s=QQ==,i=1,x", "s=QQ==,r=#{CLIENT_NONCE}x,i=1",
         "r=#{CLIENT_NONCE}x,s=QQ==", "\xFF"].each do |message|
          assert_fails(refused) { exchange.read(message) }
        end
        assert_equal 4_294_967_295, exchange.read("r=#{CLIENT_NONCE}x,s=QQ==,i=+4294967295").iterations
      end

      # Verifies: [PROTOCOL Mechanisms] the GS2 header names the channel
      # binding, and client-final's c= carries it and the data it binds.
      def test_channel_bindings_in_the_header
        assert_equal "y,,n=,r=N", Scram.new(binding: :unoffered).first("N")
        assert_equal "p=tls-exporter,,n=,r=N", Scram.new(binding: :exporter, data: "D").first("N")
        bound = Scram.new(binding: :end_point, data: "D")
        bound.first("N")
        final = bound.prove(bound.read("r=Nx,s=QQ==,i=1"), Scram.derived("p", "A", 1))

        assert final.start_with?("c=#{Scram.encode("p=tls-server-end-point,,D")},r=Nx,p=")
        assert_predicate bound, :bound?
        refute_predicate Scram.new(binding: :unoffered), :bound?
      end

      # Verifies: [PROTOCOL Mechanisms] a user's = and , are written =3D and
      # =2C in client-first; a nonce is 24 characters of base 64.
      def test_saslname_and_nonce
        assert_equal "n,,n=a=3Db=2Cc,r=N", Scram.new("a=b,c").first("N")
        assert_match(%r{\A[A-Za-z0-9+/]{24}\z}, Scram.nonce)
      end
    end
  end
end
