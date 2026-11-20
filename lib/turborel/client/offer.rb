# frozen_string_literal: true

module Turborel
  module Client
    # What a connection asks for as it opens [CLIENT What a connection
    # asks for]: the capabilities, by name; the connection's attributes,
    # each a name and a value, which the server shows in
    # INFORMATION_SCHEMA.CONNECTION_ATTRIBUTES; and the shortest request
    # sent compressed, once compression is granted.
    Offer = Data.define(:capabilities, :attributes, :compress_from)

    # The connection attribute that names the program.
    APPLICATION = "application"

    # The offers turborel-client makes.
    module Offers
      # Every capability but compression, which costs time where the
      # network is fast, and no attributes: what a connection asks for
      # unless told.
      #
      # @return [Offer]
      def self.default
        Offer.new(capabilities: Protocol::Capabilities::ALL - [Protocol::Capabilities::COMPRESSION], attributes: [],
                  compress_from: Protocol::Compression::DEFAULT_THRESHOLD)
      end

      # No capability: the protocol's first form, byte for byte.
      #
      # @return [Offer]
      def self.none = default.with(capabilities: [])

      # +offer+, asking for compression too.
      #
      # @param offer [Offer]
      # @return [Offer]
      def self.compressed(offer) = offer.with(capabilities: offer.capabilities | [Protocol::Capabilities::COMPRESSION])

      # +offer+, with the connection attribute +name+ of +value+.
      #
      # @param offer [Offer]
      # @param name [String]
      # @param value [String]
      # @return [Offer]
      def self.attribute(offer, name, value)
        pair = [name, value] #: [String, String]
        offer.with(attributes: offer.attributes + [pair])
      end
    end
  end
end
