# frozen_string_literal: true

module Turborel
  module Client
    # What cancels the statement a connection runs, from any thread
    # [CLIENT Running statements]: the cancel key Ready gave, sent as the
    # first and only message of a connection of its own [PROTOCOL Cancel
    # 'Z'].
    class Canceller
      # A canceller of the session reached at +target+ by +key+.
      #
      # @param target [Target]
      # @param key [String] the 16 bytes of the cancel key
      def initialize(target, key)
        @target = target
        @key = key
      end

      # Cancels the statement its connection runs, if one runs, waiting at
      # most +within+ seconds for each step, 10 unless told.
      #
      # @param within [Numeric]
      # @return [void]
      # @raise [Error] a connection failure if the server cannot be
      #   reached, or does not close in time
      def cancel(within = CANCEL_WITHIN)
        stream, = Transport.open(@target, within)
        begin
          stream.write_all(Protocol::Requests.cancel(@key))
          # The server closes it, saying nothing.
          stream.read_to_end(Protocol::Frame::HEADER_BYTES)
        ensure
          stream.close
        end
        nil
      end

      # Never the key.
      #
      # @return [String]
      def inspect = "#<#{self.class.name}>"
    end
  end
end
