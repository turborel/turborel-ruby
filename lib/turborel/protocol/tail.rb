# frozen_string_literal: true

module Turborel
  module Protocol
    # A message's tail [PROTOCOL The tail]: the fields version 1 gained
    # after a message's first form, each a tag u8 and its field, in
    # increasing order of tag, to the end of the body. A field is written
    # only where the capability that adds it was granted and it has
    # something to say, so a message with an empty tail is its first form
    # exactly. A tag the message does not take, or one not past the last,
    # fails the connection.
    #
    # @api private
    class Tail
      # The tags [PROTOCOL The tail].
      ATTRIBUTES = 1
      # (see ATTRIBUTES)
      MULTI = 2
      # (see ATTRIBUTES)
      CURSOR = 3
      # (see ATTRIBUTES)
      POSITION = 4
      # (see ATTRIBUTES)
      MORE = 5
      # (see ATTRIBUTES)
      ROWS = 6
      # (see ATTRIBUTES)
      SEVERITY = 7
      # (see ATTRIBUTES)
      CONSTRAINT = 15
      # (see ATTRIBUTES)
      GENERATED = 16
      # (see ATTRIBUTES)
      CONDITIONS = 17
      # (see ATTRIBUTES)
      TIME = 18
      # (see ATTRIBUTES)
      DECLARED = 19
      # (see ATTRIBUTES)
      CALLED = 20
      # The most attributes a message takes [PROTOCOL The tail].
      MAX_ATTRIBUTES = 32
      # The longest name of an attribute, in bytes [PROTOCOL The tail].
      MAX_ATTRIBUTE_NAME = 64
      # The longest value of an attribute, in bytes [PROTOCOL The tail].
      MAX_ATTRIBUTE_VALUE = 1024

      # The start of the tail +reader+ reads, of a message that takes the
      # tags +taken+.
      #
      # @param reader [Reader]
      # @param taken [Array<Integer>, Range]
      def initialize(reader, taken)
        @reader = reader
        @taken = taken
        @last = 0
      end

      # Each tag of the tail, in turn, its field left for the block to read.
      #
      # @yieldparam tag [Integer]
      # @return [void]
      # @raise [Error] a connection failure of a tag not taken, or not past
      #   the last
      def each_tag
        until @reader.at_end?
          tag = @reader.u8
          raise @reader.corrupt("its tail has tag #{tag} out of place") if tag <= @last || !@taken.include?(tag)

          @last = tag
          yield tag
        end
      end

      # Writes the attributes +attributes+, under their tag, unless there
      # are none.
      #
      # @param writer [Writer]
      # @param attributes [Array<Array(String, String)>] each a name and a value
      # @return [void]
      # @raise [Error] SQLSTATE 08006, the code the server would fail the
      #   connection with, of more than 32 attributes, or a name or value
      #   out of its bounds; refused before it is sent, the connection kept
      def self.put_attributes(writer, attributes)
        return if attributes.empty?
        if attributes.size > MAX_ATTRIBUTES
          raise Error.connection_failure("#{attributes.size} attributes are more than the 32 taken")
        end

        writer.u8(ATTRIBUTES).u32(attributes.size)
        attributes.each { |name, value| put_attribute(writer, Writer.utf8(name), Writer.utf8(value)) }
      end

      # Writes an attribute's +name+ and +value+, each UTF-8.
      #
      # @return [void]
      # @raise [Error] SQLSTATE 08006 of a name or value out of its bounds
      def self.put_attribute(writer, name, value)
        unless attribute?(name, value)
          raise Error.connection_failure("an attribute's name is 1 to 64 bytes and its value at most 1024")
        end

        writer.str(name).str(value)
      end

      # @param name [String] UTF-8
      # @param value [String] UTF-8
      # @return [Boolean] whether both are within their bounds
      def self.attribute?(name, value)
        name.bytesize.between?(1, MAX_ATTRIBUTE_NAME) && value.bytesize <= MAX_ATTRIBUTE_VALUE
      end
    end
  end
end
