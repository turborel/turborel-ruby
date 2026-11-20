# frozen_string_literal: true

require "test_helper"

module Turborel
  module Protocol
    # What the value codec shares.
    class ValuesTest < Minitest::Test
      # Verifies: [PROTOCOL Values] a DECFLOAT is in its one form: zero as 0
      # and 0, no trailing zero, at most 34 digits, its adjusted exponent
      # from -6143 to 6144.
      def test_decfloat_form
        assert Values.decfloat?(0, 0)
        assert Values.decfloat?(-1, -6143)
        assert Values.decfloat?((10**34) - 1, 6144 - 33)
        refute Values.decfloat?(0, 1)
        refute Values.decfloat?(-20, 0)
        refute Values.decfloat?(10**34, 0)
        refute Values.decfloat?(1, -6144)
        refute Values.decfloat?(1, 6145)
      end
    end
  end
end
