# frozen_string_literal: true

require "test_helper"

module Turborel
  # The gem's version.
  class VersionTest < Minitest::Test
    # Verifies: [DESIGN] D5 the version is the Turborel release's, 0.0.0 in
    # the alpha.
    def test_version_is_the_alpha
      assert_equal "0.0.0", VERSION
    end
  end
end
