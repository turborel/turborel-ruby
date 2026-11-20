# frozen_string_literal: true

module Turborel
  module Client
    # A large object's octets as a stream, a chunk read at a time
    # [CLIENT Large objects]: read and readpartial as an IO's, so
    # IO.copy_stream copies it.
    class LobReader
      # A reader of +lob+ over +connection+.
      #
      # @param connection [Connection]
      # @param lob [Lob]
      def initialize(connection, lob)
        @connection = connection
        @lob = lob
        @at = 0
        @chunk = "".b
      end

      # At most +length+ octets, +nil+ at the end; all that is left if
      # +length+ is +nil+.
      #
      # @param length [Integer, nil]
      # @param buffer [String, nil] what the octets are put in
      # @return [String, nil] binary
      # @raise [Error] as Connection#read_lob's; a connection failure if the
      #   server sends less than the large object's length
      def read(length = nil, buffer = nil)
        taken = length ? take(length) : all
        return nil if taken.nil? && length&.positive?

        taken ||= "".b
        buffer ? buffer.replace(taken) : taken
      end

      # At most +length+ octets, at least one, as an IO's readpartial.
      #
      # @param length [Integer]
      # @param buffer [String, nil]
      # @return [String] binary
      # @raise [EOFError] at the end
      def readpartial(length, buffer = nil)
        read(length, buffer) || raise(EOFError, "the end of the large object")
      end

      # @return [Boolean] whether every octet was read
      def eof? = @chunk.empty? && @at >= @lob.octets

      private

      # At most +length+ octets from the chunk, the next chunk read when
      # it is spent; +nil+ at the end.
      def take(length)
        return "".b if length.zero?
        return nil if eof?

        refill if @chunk.empty?
        taken = @chunk.byteslice(0, length) || "".b
        @chunk = @chunk.byteslice(taken.bytesize, @chunk.bytesize) || "".b
        taken
      end

      # Every octet left.
      def all
        out = "".b
        while (piece = take(Lobs::CHUNK_OCTETS))
          out << piece
        end
        out
      end

      # Reads the next chunk.
      def refill
        @chunk = @connection.read_lob(@lob, @at, Lobs::CHUNK_OCTETS)
        raise Error.connection_failure("the server sent less of the large object than its length") if @chunk.empty?

        @at += @chunk.bytesize
      end
    end

    # A new large object written a piece at a time, sent in Appends of at
    # most a chunk, a character one cut where a character ends; finish
    # gives the value to send as a parameter [CLIENT Large objects].
    class LobWriter
      # @return [Symbol] +:character+ or +:binary+
      attr_reader :kind

      # A writer of the large object of +kind+ and +locator+ over
      # +connection+.
      #
      # @api private
      def initialize(connection, kind, locator)
        @connection = connection
        @kind = kind
        @locator = locator
        @pending = "".b
        @octets = 0
        @characters = 0
      end

      # Writes +pieces+, each a String's octets; a character's octets may
      # be split between writes.
      #
      # @param pieces [Array<String>]
      # @return [Integer] the octets written
      # @raise [Error] a connection failure; the server's
      def write(*pieces)
        pieces.sum { |piece| written(piece.b) }
      end

      # Writes +piece+, as write does.
      #
      # @return [LobWriter] itself
      def <<(piece)
        write(piece)
        self
      end

      # Sends what is written and not yet sent.
      #
      # @return [void]
      def flush
        return if @pending.empty?

        @connection.lob_append(@locator, @pending)
        @pending = "".b
      end

      # The large object written, to send as a parameter by its locator:
      # valid until its transaction ends, and used once.
      #
      # @return [Lob]
      # @raise [Error] a connection failure; the server's: 22021 if a
      #   character one's octets are not UTF-8, 22001 if it is too long
      def finish
        flush
        Lob.new(kind:, data: nil, locator: @locator, octets: @octets, characters: kind == :character ? @characters : 0)
      end

      private

      # Takes +bytes+: counted, and sent a chunk at a time.
      def written(bytes)
        @pending << bytes
        @octets += bytes.bytesize
        @characters += bytes.each_byte.count { |byte| !Lobs.continuation?(byte) } if kind == :character
        append_piece while @pending.bytesize >= Lobs::CHUNK_OCTETS
        bytes.bytesize
      end

      # Sends the first chunk of what is pending, a character string cut
      # where a character ends.
      def append_piece
        cut = kind == :character ? Lobs.char_cut(@pending, Lobs::CHUNK_OCTETS) : Lobs::CHUNK_OCTETS
        cut = cut.clamp(1, @pending.bytesize)
        @connection.lob_append(@locator, @pending.byteslice(0, cut) || "".b)
        @pending = @pending.byteslice(cut, @pending.bytesize) || "".b
      end
    end
  end
end
