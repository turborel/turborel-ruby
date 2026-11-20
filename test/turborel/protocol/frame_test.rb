# frozen_string_literal: true

require "test_helper"

module Turborel
  module Protocol
    # The frame header, encoded and decoded.
    class FrameTest < Minitest::Test
      # Ping's kind, 'G', from the worked example.
      PING = 0x47
      # Hello's kind, 'H', from the worked example.
      HELLO = 0x48
      # The worked example's Hello body, 36 bytes.
      HELLO_LENGTH = 36

      # Verifies: [PROTOCOL A worked example] a Ping is a header alone,
      # kind 'G' and length 0, the five bytes 47 00 00 00 00.
      def test_ping_header_is_the_worked_examples_bytes
        bytes = Frame.encode_header(PING, 0)

        assert_equal "\x47\x00\x00\x00\x00".b, bytes
        assert_equal [PING, 0], Frame.decode_header(bytes)
      end

      # Verifies: [PROTOCOL A worked example] the Hello's header is kind 'H'
      # then its body's length, 36, little-endian.
      def test_hello_header_is_the_worked_examples_bytes
        bytes = Frame.encode_header(HELLO, HELLO_LENGTH)

        assert_equal "\x48\x24\x00\x00\x00".b, bytes
        assert_equal [HELLO, HELLO_LENGTH], Frame.decode_header(bytes)
      end

      # Verifies: [PROTOCOL Frames] the header is five bytes, the kind a u8
      # and the length a u32 least significant byte first, at both ends of
      # their ranges.
      def test_header_round_trips_at_the_edges_of_its_fields
        bytes = Frame.encode_header(Frame::MAX_KIND, Frame::MAX_LENGTH)

        assert_equal Frame::HEADER_BYTES, bytes.bytesize
        assert_equal Encoding::BINARY, bytes.encoding
        assert_equal "\xFF\xFF\xFF\xFF\xFF".b, bytes
        assert_equal [Frame::MAX_KIND, Frame::MAX_LENGTH], Frame.decode_header(bytes, Frame::MAX_LENGTH)
        assert_equal "\x00\x01\x02\x03\x04".b, Frame.encode_header(0, 0x0403_0201)
      end

      # Verifies: [PROTOCOL Frames] the client takes a body of up to 16 MiB
      # unless told otherwise, and a longer one fails the connection
      # (SQLCODE -919, SQLSTATE 08006).
      def test_body_longer_than_taken_fails_the_connection
        assert_equal [PING, Frame::MAX_BODY], Frame.decode_header(Frame.encode_header(PING, Frame::MAX_BODY))

        failure = assert_raises(Error) { Frame.decode_header(Frame.encode_header(PING, Frame::MAX_BODY + 1)) }
        assert_connection_failure failure
        failure = assert_raises(Error) { Frame.decode_header(Frame.encode_header(PING, 2), 1) }
        assert_connection_failure failure
      end

      # Verifies: [PROTOCOL Frames] a header cut short fails the connection.
      def test_header_cut_short_fails_the_connection
        assert_connection_failure assert_raises(Error) { Frame.decode_header("\x47\x00\x00\x00".b) }
        assert_connection_failure assert_raises(Error) { Frame.decode_header("".b) }
        assert_connection_failure assert_raises(Error) { Frame.decode_header("\x47\x00\x00\x00\x00\x00".b) }
      end

      # Verifies: [PROTOCOL Frames] a kind is a u8 and a length a u32, so a
      # value either field cannot hold is refused before anything is sent.
      def test_fields_out_of_range_are_refused
        assert_connection_failure assert_raises(Error) { Frame.encode_header(Frame::MAX_KIND + 1, 0) }
        assert_connection_failure assert_raises(Error) { Frame.encode_header(-1, 0) }
        assert_connection_failure assert_raises(Error) { Frame.encode_header(PING, Frame::MAX_LENGTH + 1) }
        assert_connection_failure assert_raises(Error) { Frame.encode_header(PING, -1) }
      end

      private

      def assert_connection_failure(failure)
        assert_equal Error::CONNECTION_FAILURE_SQLCODE, failure.sqlcode
        assert_equal Error::CONNECTION_FAILURE_SQLSTATE, failure.sqlstate
        assert_nil failure.rule
        assert_nil failure.position
      end
    end
  end
end
