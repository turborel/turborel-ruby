# frozen_string_literal: true

require "test_helper"

module Turborel
  module Client
    # The mechanisms with nothing to exchange.
    class MechanismsTest < Minitest::Test
      include TestSupport

      # Verifies: [PROTOCOL Mechanisms] trust sends nothing and is not
      # secret; it has no answer to a challenge.
      def test_trust
        trust = Trust.new

        assert_equal ["trust", "", false], [trust.name, trust.initial, trust.secret?]
        assert_fails { trust.answer("x") }
        assert_nil trust.ready!
        assert_nil trust.bind(nil)
        assert_nil trust.refused
      end

      # Verifies: [PROTOCOL Mechanisms] password sends the password's UTF-8
      # and is secret, never shown.
      def test_password
        password = Password.new("é")

        assert_equal ["password", "\xC3\xA9".b, true], [password.name, password.initial, password.secret?]
        assert_equal "#<Turborel::Client::Password>", password.inspect
      end

      # Verifies: [PROTOCOL Mechanisms] certificate sends nothing, its proof
      # the certificate presented over TLS.
      def test_certificate
        assert_equal ["certificate", ""], [Certificate.new.name, Certificate.new.initial]
        assert_raises(NotImplementedError) { Mechanism.new.name }
      end
    end
  end
end
