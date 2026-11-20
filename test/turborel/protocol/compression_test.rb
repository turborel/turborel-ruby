# frozen_string_literal: true

require "test_helper"

module Turborel
  module Protocol
    # Compressed frames.
    class CompressionTest < Minitest::Test
      include TestSupport

      # A body that compresses well.
      LONG = ("SELECT 1 " * 400).b
      # The kinds of Query and Ping.
      QUERY = "Q".ord
      # (see QUERY)
      PING = "G".ord

      # Verifies: [PROTOCOL Compressed frames] a frame is sent as kind z: the
      # held frame's kind, its body's length, then a zlib stream of the body.
      def test_frame_is_compressed_as_kind_z
        plain = Frame.encode(QUERY, LONG)
        compressed = Compression.compress_frames(plain)
        kind, length = Frame.decode_header(compressed.byteslice(0, 5) || "")
        body = compressed.byteslice(5, length) || ""

        assert_equal Compression::COMPRESSED, kind
        assert_operator compressed.bytesize, :<, plain.bytesize
        assert_equal [QUERY, plain.byteslice(5..)], Compression.decompress(body)
        assert_equal Zlib::Deflate.deflate(plain.byteslice(5..) || ""), body.byteslice(5..)
      end

      # Verifies: [PROTOCOL Compressed frames] the client chooses its
      # threshold, and sends a frame as it is where it is shorter than the
      # threshold or compressing would not shorten it.
      def test_threshold_and_frames_that_would_not_shorten
        short = Frame.encode(PING, "") + Frame.encode(QUERY, "VALUES 1")

        assert_equal short, Compression.compress_frames(short)
        assert_equal short, Compression.compress_frames(short, 0)
        long = Frame.encode(QUERY, LONG)

        assert_equal long, Compression.compress_frames(long, long.bytesize + 1)
        assert_equal Compression::COMPRESSED, Compression.compress_frames(long, long.bytesize).getbyte(0)
        mixed = Compression.compress_frames(long + short)

        assert mixed.end_with?(short)
      end

      # Verifies: [PROTOCOL Compressed frames] a z frame is inflated to at most
      # its length, itself at most the longest body taken; past either, or a
      # stream inflating to another length, fails the connection.
      def test_inflating_is_bounded_by_the_length
        stream = Zlib::Deflate.deflate(LONG)

        assert_equal LONG, Compression.decompress(writer.u8(81).u32(LONG.bytesize).raw(stream).to_s).last
        assert_fails { Compression.decompress(writer.u8(81).u32(LONG.bytesize - 1).raw(stream).to_s) }
        assert_fails { Compression.decompress(writer.u8(81).u32(LONG.bytesize + 1).raw(stream).to_s) }
        assert_fails { Compression.decompress(writer.u8(81).u32(LONG.bytesize).raw(stream).to_s, LONG.bytesize - 1) }
        bomb = Zlib::Deflate.deflate("\x00" * (16 * 1024 * 1024))

        assert_fails { Compression.decompress(writer.u8(81).u32(1024).raw(bomb).to_s) }
      end

      # Verifies: [PROTOCOL Compressed frames] a z frame that holds another z
      # frame, a stream that is not zlib, or bytes after the stream fail the
      # connection.
      def test_malformed_z_frames_fail
        stream = Zlib::Deflate.deflate("abc")

        assert_fails { Compression.decompress(writer.u8(Compression::COMPRESSED).u32(3).raw(stream).to_s) }
        assert_fails { Compression.decompress(writer.u8(81).u32(3).raw("not zlib").to_s) }
        assert_fails { Compression.decompress(writer.u8(81).u32(3).raw("#{stream}X").to_s) }
        assert_fails { Compression.decompress(writer.u8(81).u32(3).raw(stream.byteslice(0, 4) || "").to_s) }
        assert_fails { Compression.decompress(hex("51 03")) }
      end
    end
  end
end
