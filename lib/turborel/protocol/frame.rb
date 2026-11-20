# frozen_string_literal: true

module Turborel
  # The native protocol, version 1: its messages and their encoding,
  # without I/O, so the codec is tested byte by byte (RULES.md D1).
  #
  # @api private
  module Protocol
    # A frame's header [PROTOCOL Frames]: the kind of its message, a u8,
    # then the length of its body, a u32 little-endian, the header not
    # counted.
    #
    # @api private
    module Frame
      # The bytes of a header: the kind, then the length.
      HEADER_BYTES = 5
      # The longest body a reply may have unless the program says
      # otherwise: 16 MiB, the server's own default, so a peer cannot make
      # the client hold memory without bound [PROTOCOL Frames].
      MAX_BODY = 16 * 1024 * 1024
      # The largest kind a u8 holds.
      MAX_KIND = 0xFF
      # The largest length a u32 holds.
      MAX_LENGTH = 0xFFFF_FFFF
      # Array#pack's directives of a header: an unsigned 8-bit kind, then
      # an unsigned 32-bit little-endian length.
      LAYOUT = "CV"

      # A frame of +kind+ whose body is +body+: its header, then the body.
      #
      # @param kind [Integer] the message's kind, 0 to 255
      # @param body [String] the body's octets
      # @return [String] binary
      # @raise [Error] if the kind or the body's length does not fit its field
      def self.encode(kind, body) = encode_header(kind, body.bytesize) + body.b

      # The header of a frame of +kind+ whose body is +length+ bytes.
      #
      # @param kind [Integer] the message's kind, 0 to 255
      # @param length [Integer] the body's bytes, 0 to 2**32 - 1
      # @return [String] five bytes, binary
      # @raise [Error] a connection failure if either does not fit its field
      def self.encode_header(kind, length)
        raise Error.connection_failure("a message's kind #{kind} does not fit a u8") unless kind.between?(0, MAX_KIND)
        unless length.between?(0, MAX_LENGTH)
          raise Error.connection_failure("a message of #{length} bytes does not fit a u32")
        end

        [kind, length].pack(LAYOUT)
      end

      # The kind and the body's length of the frame whose header is
      # +header+.
      #
      # @param header [String] the header's five bytes
      # @param max [Integer] the longest body taken
      # @return [Array(Integer, Integer)] the kind and the body's length
      # @raise [Error] a connection failure if the header is not five bytes
      #   or the body would be longer than +max+
      def self.decode_header(header, max = MAX_BODY)
        unless header.bytesize == HEADER_BYTES
          raise Error.connection_failure("a frame's header of #{header.bytesize} bytes is not #{HEADER_BYTES}")
        end

        # String#unpack's type depends on its directives, which only run
        # time reads; LAYOUT's give two Integers, so Steep is told so.
        # @type var fields: [Integer, Integer]
        fields = _ = header.unpack(LAYOUT)
        kind, length = fields
        raise Error.connection_failure("a message of #{length} bytes is longer than the #{max} taken") if length > max

        [kind, length]
      end
    end
  end
end
