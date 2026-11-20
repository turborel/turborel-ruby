# frozen_string_literal: true

module Turborel
  module Client
    # A connection's large objects [CLIENT Large objects]: a range read by
    # its locator, or of one held whole; the whole read as a stream, a
    # chunk at a time; a new one written a piece at a time; a locator freed
    # or held past its transaction's commit.
    module Lobs
      # The most octets read or appended at a time, turborel's
      # CHUNK_OCTETS: 256 KiB.
      CHUNK_OCTETS = 256 * 1024
      # The longest value sent whole for a large object parameter, as the
      # server sends one whole by default (SERVER.LOB_INLINE_BYTES): 64 KiB.
      INLINE_OCTETS = 64 * 1024

      # At most +count+ octets of +lob+ from octet +from+, from 0; of a
      # character large object, its whole characters if +characters+.
      # Fewer than asked only at its end, or at a chunk's [PROTOCOL Lob 'L'].
      #
      # @param lob [Lob]
      # @param from [Integer]
      # @param count [Integer]
      # @param characters [Boolean]
      # @return [String] binary
      # @raise [Error] SQLSTATE 0F001 if its locator is no longer valid;
      #   22000 of a large object the server did not send; a connection
      #   failure
      def read_lob(lob, from, count, characters: false)
        data = lob.data
        return Lobs.held_range(lob, data, from, count, characters) if data

        send_frame(Protocol::Requests.lob_read(located(lob, "was not sent by the server"), from, count, characters:))
        reply = expect(Protocol::Replies::LobData, Protocol::Replies::LobLocator)
        raise lose("the server sent a locator for a Read") if reply.is_a?(Protocol::Replies::LobLocator)

        reply.data.b
      end

      # +lob+'s octets as a stream, read a chunk at a time.
      #
      # @param lob [Lob]
      # @return [LobReader]
      def lob_reader(lob) = LobReader.new(_ = self, lob)

      # A new large object of +kind+, +:character+ or +:binary+, written a
      # piece at a time.
      #
      # @param kind [Symbol]
      # @return [LobWriter]
      # @raise [Error] TB910 of another kind; a connection failure; the
      #   server's
      def create_lob(kind)
        send_frame(Protocol::Requests.lob_create(kind))
        reply = expect(Protocol::Replies::LobData, Protocol::Replies::LobLocator)
        raise lose("the server sent data for a Create") if reply.is_a?(Protocol::Replies::LobData)

        LobWriter.new(_ = self, kind, reply.locator)
      end

      # +lob+'s locator no longer valid, nor the value it named.
      #
      # @param lob [Lob]
      # @return [Completion]
      # @raise [Error] SQLSTATE 0F001 if it is not valid; 22000 of one sent
      #   whole; a connection failure
      def free_lob(lob)
        send_frame(Protocol::Requests.lob_free(located(lob, "was sent whole: it has no locator")))
        completion_reply
      end

      # +lob+'s locator valid past its transaction's commit, until freed or
      # a transaction is rolled back.
      #
      # @param lob [Lob]
      # @return [Completion]
      # @raise [Error] as free_lob's
      def hold_lob(lob)
        send_frame(Protocol::Requests.lob_hold(located(lob, "was sent whole: it has no locator")))
        completion_reply
      end

      # Appends +octets+ to the large object of +locator+.
      #
      # @api private
      # @return [void]
      def lob_append(locator, octets)
        send_frame(Protocol::Requests.lob_append(locator, octets))
        completion_reply
      end

      # The range of +data+, +lob+'s octets held whole, in characters if
      # +characters+ and it is a character one.
      #
      # @api private
      # @return [String] binary
      def self.held_range(lob, data, from, count, characters)
        return data.b.byteslice(from, count) || "".b unless characters && lob.kind == :character

        (data.dup.force_encoding(Encoding::UTF_8).scrub[from, count] || "").b
      end

      # Cuts +bytes+, UTF-8, at most +most+ octets in, where a character
      # ends: the octets before the cut, turborel's char_cut. A character
      # the end of +bytes+ splits is left out, its rest yet to come; 0 if no
      # character ends within +most+.
      #
      # @api private
      # @return [Integer]
      def self.char_cut(bytes, most)
        cut = [most, bytes.bytesize].min
        return lead_at_or_before(bytes, cut) if cut < bytes.bytesize

        lead = last_lead(bytes, cut)
        lead && lead + width(bytes.getbyte(lead) || 0) > cut ? lead : cut
      end

      # The octet at or before +cut+ that begins a character, 0 if none.
      #
      # @api private
      def self.lead_at_or_before(bytes, cut)
        cut -= 1 while cut.positive? && continuation?(bytes.getbyte(cut))
        cut
      end

      # The lead octet of the character the end of +bytes+, +cut+ long,
      # is in, at most 4 back; +nil+ if none.
      #
      # @api private
      def self.last_lead(bytes, cut)
        (1..4).map { |back| cut - back }.find { |at| !at.negative? && !continuation?(bytes.getbyte(at)) }
      end

      # Whether +byte+ continues a UTF-8 character.
      #
      # @api private
      def self.continuation?(byte) = !byte.nil? && (byte & 0xC0) == 0x80

      # The octets of the UTF-8 character whose lead octet is +byte+.
      #
      # @api private
      def self.width(byte)
        ones = 0
        ones += 1 while ones < 8 && byte[7 - ones] == 1
        ones.between?(2, 4) ? ones : 1
      end

      private

      # The locator of +lob+, which must have one: a data exception saying
      # it +why+ if not.
      def located(lob, why)
        lob.locator || raise(Error.data_exception("the large object #{why}"))
      end
    end
  end
end
