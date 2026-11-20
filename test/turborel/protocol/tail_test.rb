# frozen_string_literal: true

require "test_helper"

module Turborel
  module Protocol
    # A message's tail.
    class TailTest < Minitest::Test
      include TestSupport

      # Verifies: [PROTOCOL The tail] tags come in increasing order, each one
      # the message takes, and the tail ends with the body.
      def test_tags_are_read_in_order
        fields = reader(hex("01 03 05"))
        tags = []
        Tail.new(fields, [1, 3, 5]).each_tag { |tag| tags << tag }

        assert_equal [1, 3, 5], tags
      end

      # Verifies: [PROTOCOL The tail] a tag the message does not take, or one
      # not past the last, fails the connection.
      def test_tags_out_of_place_fail
        assert_fails { Tail.new(reader(hex("02")), [1]).each_tag { nil } }
        assert_fails { Tail.new(reader(hex("03 03")), [3]).each_tag { nil } }
        assert_fails { Tail.new(reader(hex("05 04")), [4, 5]).each_tag { nil } }
      end

      # Verifies: [PROTOCOL The tail] attributes are a count then each name
      # and value, written only where there are some.
      def test_attributes_are_counted_names_and_values
        assert_equal "", writer.tap { |w| Tail.put_attributes(w, []) }.to_s
        bytes = writer.tap { |w| Tail.put_attributes(w, [%w[a b]]) }.to_s

        assert_equal hex("01 01000000 01000000 61 01000000 62"), bytes
      end

      # Verifies: [PROTOCOL The tail] a message takes at most 32 attributes,
      # a name of 1 to 64 bytes and a value of at most 1024; more is refused
      # before it is sent.
      def test_attributes_are_bounded
        assert_equal 32, writer.tap { |w|
          Tail.put_attributes(w, Array.new(32) {
            ["n", "v" * 1024]
          })
        }.to_s[1, 4].unpack1("V")
        assert_fails(BEYOND) { Tail.put_attributes(writer, Array.new(33) { %w[n v] }) }
        assert_fails(BEYOND) { Tail.put_attributes(writer, [["", "v"]]) }
        assert_fails(BEYOND) { Tail.put_attributes(writer, [["n" * 65, "v"]]) }
        assert_fails(BEYOND) { Tail.put_attributes(writer, [["n", "v" * 1025]]) }
      end
    end
  end
end
