# frozen_string_literal: true

require "zlib"

module Turborel
  module Protocol
    # Compressed frames [PROTOCOL Compressed frames]: once the capability
    # `compression` is granted, either side may send a frame as one of
    # kind `z`, holding the kind of the frame it carries, the length of
    # that frame's body, then a zlib stream of the body (RFC 1950).
    #
    # @api private
    module Compression
      # The kind of a compressed frame.
      COMPRESSED = "z".ord
      # The threshold the client compresses at unless told another: a
      # frame whose whole length, header included, is at least this many
      # bytes, turborel-client's DEFAULT_THRESHOLD.
      DEFAULT_THRESHOLD = 1024
      # The bytes a compressed frame's body takes before its stream: the
      # kind u8 and the length u32.
      PREFIX_BYTES = 5
      # The most bytes of the stream inflated at a time, so no piece of it
      # can make the reader hold much more than the length it declares.
      INFLATE_CHUNK = 1024

      # +frames+, frames already encoded one after another, each whose
      # whole length is at least +threshold+ compressed where the
      # compressed frame comes out shorter, the others as they are.
      #
      # @param frames [String]
      # @param threshold [Integer]
      # @return [String] binary
      def self.compress_frames(frames, threshold = DEFAULT_THRESHOLD)
        reader = Reader.new(frames, "frame")
        out = +"".b
        out << compressed(reader.u8, reader.bytes, threshold) until reader.at_end?
        out
      end

      # The frame of +kind+ and +body+, compressed if it is long enough and
      # comes out shorter.
      #
      # @return [String]
      def self.compressed(kind, body, threshold)
        plain = Frame.encode(kind, body)
        return plain if plain.bytesize < threshold

        stream = Zlib::Deflate.deflate(body)
        return plain unless stream.bytesize + PREFIX_BYTES < body.bytesize

        Frame.encode(COMPRESSED, Writer.new.u8(kind).u32(body.bytesize).raw(stream).to_s)
      end

      # The kind and body of the frame the body of a `z` frame holds,
      # inflating at most the length it declares.
      #
      # @param body [String] the `z` frame's body
      # @param max [Integer] the longest body taken
      # @return [Array(Integer, String)]
      # @raise [Error] a connection failure of a `z` frame within a `z`
      #   frame, a length past +max+, a stream that is not zlib or inflates
      #   to another length
      def self.decompress(body, max = Frame::MAX_BODY)
        reader = Reader.new(body, "compressed frame")
        kind = reader.u8
        length = reader.u32
        raise reader.corrupt("a compressed frame holds another") if kind == COMPRESSED
        raise reader.corrupt("a compressed message of #{length} bytes is longer than the #{max} taken") if length > max

        [kind, inflate(reader.rest, length)]
      end

      # The data of the zlib stream +stream+, which must be all of it, of
      # exactly +length+ bytes.
      #
      # @return [String]
      def self.inflate(stream, length)
        inflater = Zlib::Inflate.new
        begin
          data = inflate_pieces(inflater, stream, length)
          raise Error.connection_failure("a compressed frame inflates to another length than it declares") unless
            inflater.finished? && inflater.total_in == stream.bytesize && data.bytesize == length

          data
        rescue Zlib::Error => e
          raise Error.connection_failure("a compressed frame's stream is not zlib: #{e.message}")
        ensure
          # A stream given up on before its end is reset first, as closing it
          # unfinished would warn.
          inflater.reset unless inflater.finished?
          inflater.close
        end
      end

      # Inflates +stream+ a piece at a time, failing as soon as the data
      # passes +length+.
      #
      # @return [String]
      def self.inflate_pieces(inflater, stream, length)
        data = +"".b
        (0...stream.bytesize).step(INFLATE_CHUNK) do |at|
          inflater.inflate(stream.byteslice(at, INFLATE_CHUNK) || "") do |chunk|
            data << chunk
            if data.bytesize > length
              raise Error.connection_failure("a compressed frame inflates past its #{length} bytes")
            end
          end
          break if inflater.finished?
        end
        data
      end
    end
  end
end
