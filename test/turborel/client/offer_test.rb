# frozen_string_literal: true

require "test_helper"

module Turborel
  module Client
    # What a connection asks for.
    class OfferTest < Minitest::Test
      # Verifies: [CLIENT What a connection asks for] an offer of the
      # program's own: none, compression, connection attributes.
      def test_offers
        assert_equal Protocol::Capabilities::ALL - ["compression"], Offers.default.capabilities
        assert_empty Offers.none.capabilities
        assert_includes Offers.compressed(Offers.none).capabilities, "compression"
        assert_equal Offers.compressed(Offers.default), Offers.compressed(Offers.compressed(Offers.default))
        assert_equal [[APPLICATION, "app"]], Offers.attribute(Offers.none, APPLICATION, "app").attributes
        assert_equal Protocol::Compression::DEFAULT_THRESHOLD, Offers.default.compress_from
      end
    end
  end
end
