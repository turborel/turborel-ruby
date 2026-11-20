# frozen_string_literal: true

require "test_helper"

module Turborel
  module Client
    # The client's side of scram-sha-256, as a mechanism.
    class ScramTest < Minitest::Test
      include TestSupport

      # A server's side of the exchange, for the password "pencil" under
      # salt "salt" and iterations 2, answering client-first and
      # client-final as a server would, its signature right or not.
      def serve(mechanism, signature_right: true)
        first = mechanism.initial
        nonce = first.split("r=").last
        server_first = "r=#{nonce}srv,s=#{Protocol::Scram.encode("salt")},i=2"
        final = mechanism.answer(server_first)
        keys = Protocol::Scram.derived("pencil", "salt", 2)
        auth = "#{first.sub(/\A[^,]*,[^,]*,/, "")},#{server_first},#{final.sub(/,p=.*\z/, "")}"
        signature = signature_right ? OpenSSL::HMAC.digest("SHA256", keys.server, auth) : "\x00" * 32
        [first, mechanism.answer("v=#{Protocol::Scram.encode(signature)}")]
      end

      # Verifies: [CLIENT Connecting] SCRAM-SHA-256 proves the password,
      # never sending it, and takes the server only once it proved it knows
      # the verifier; the password never shown.
      def test_proves_and_checks_the_server
        mechanism = Scram.new("pencil")
        first, last = serve(mechanism)

        assert first.start_with?("n,,n=,r=")
        assert_equal "", last
        assert_nil mechanism.ready!
        refute_includes mechanism.inspect, "pencil"
        assert_fails { Scram.new("pencil").ready! }
      end

      # Verifies: [CLIENT Connecting] a server that does not prove it knows
      # the verifier is refused (28000), and the keys the cache gave for the
      # failed exchange are forgotten.
      def test_wrong_signature_refused_and_forgotten
        cache = KeyCache.new
        mechanism = Scram.new("pencil", cache:)

        assert_fails([-919, "28000"]) { serve(mechanism, signature_right: false) }
        assert_equal 0, cache.size
        assert_fails { Scram.new("p").answer("r=x") }
      end

      # Verifies: [CLIENT The SCRAM key cache] a mechanism given a cache
      # derives the keys once, a second login of the same salt and iterations
      # finding them; a refused login forgets them.
      def test_cache_given_to_a_mechanism
        cache = KeyCache.new
        2.times { serve(Scram.new("pencil", cache:)) }

        assert_equal [1, 1], cache.lookups
        mechanism = Scram.new("pencil", cache:)
        serve(mechanism)
        mechanism.refused

        assert_equal 0, cache.size
      end

      # Verifies: [CLIENT Connecting] over TLS 1.3 it is scram-sha-256-plus
      # bound by tls-exporter, else by the server certificate's hash; of a
      # certificate that defines no binding, scram-sha-256 offered none (y);
      # disable binds nothing, and require refuses an unbound exchange.
      def test_channel_binding
        exporter = Scram.new("p").tap { |m| m.bind(TlsChannel.new(certificate: nil, exporter: "E" * 32)) }

        assert_equal Protocol::Scram::MECHANISM_PLUS, exporter.name
        assert exporter.initial.start_with?("p=tls-exporter,,")
        unoffered = Scram.new("p").tap { |m| m.bind(TlsChannel.new(certificate: "no", exporter: nil)) }

        assert unoffered.initial.start_with?("y,,")
        disabled = Scram.new("p", binding: :disable).tap { |m| m.bind(TlsChannel.new(certificate: nil, exporter: "E")) }

        assert_equal Protocol::Scram::MECHANISM, disabled.name
        required = Scram.new("pencil", binding: :require)
        nonce = required.initial.split("r=").last
        assert_fails([-919, "28000"]) { required.answer("r=#{nonce}x,s=QQ==,i=1") }
        assert_fails(UNSUPPORTED) { Scram.new("p", binding: :maybe) }
      end

      # Verifies: [CLIENT Connecting] SCRAM is refused over plain TCP unless
      # asked for in the clear.
      def test_secret_unless_in_the_clear
        assert_predicate Scram.new("p"), :secret?
        refute_predicate Scram.new("p", clear: true), :secret?
      end
    end
  end
end
