# frozen_string_literal: true

require "test_helper"
require_relative "../../support/fake_server"

module Turborel
  module Client
    # A connection's large objects, against a server of the test's own
    # script.
    class LobsTest < Minitest::Test
      include TestSupport

      # A large object by locator 9 of +octets+ octets and +characters+
      # characters.
      def located(kind = :binary, octets = 10, characters = 10)
        Lob.new(kind:, data: nil, locator: 9, octets:, characters:)
      end

      def data(bytes) = Protocol::Writer.new.u8(0).bytes(bytes)

      # Runs +script+ after login, then reads Terminate; gives the
      # connection and the server.
      def scripted(&)
        server = FakeServer.new do |peer|
          peer.frame
          peer.ready(Protocol::Capabilities::ALL - [Protocol::Capabilities::COMPRESSION])
          frames = []
          yield(peer, frames)
          frames << peer.frame
          frames
        end
        [Client.connect_to(server.target, user: "ann", mechanism: Trust.new), server]
      end

      # Verifies: [PROTOCOL Lob 'L'] read of a locator: from, count and the
      # characters flag, answered by a Lob reply of data; a locator in its
      # place loses the connection.
      def test_read_by_locator
        connection, server = scripted do |peer, frames|
          frames << peer.frame
          peer.reply("L", data("abc"))
          frames << peer.frame
          peer.reply("L", Protocol::Writer.new.u8(1).u32(4))
        end

        assert_equal "abc".b, connection.read_lob(located, 2, 3, characters: true)
        assert_fails { connection.read_lob(located, 0, 1) }
        assert_predicate connection, :lost?
        connection.instance_variable_get(:@stream).close
        read, = server.join

        assert_equal Protocol::Requests.lob_read(9, 2, 3, characters: true), Protocol::Frame.encode(*read)
      end

      # Verifies: [CLIENT Large objects] a large object held whole read by
      # range, of octets or of a CLOB's characters, with no round trip; one
      # neither held nor located refused (22000).
      def test_ranges_of_one_held_whole
        connection, = scripted { nil }
        clob = Lob.new(kind: :character, data: "héllo", locator: nil, octets: 6, characters: 5)
        blob = Lob.new(kind: :binary, data: "\x01\x02\x03".b, locator: nil, octets: 3, characters: 0)

        assert_equal "éll".b, connection.read_lob(clob, 1, 3, characters: true)
        assert_equal "\xC3\xA9".b, connection.read_lob(clob, 1, 2)
        assert_equal "\x02\x03".b, connection.read_lob(blob, 1, 9, characters: true)
        assert_equal "".b, connection.read_lob(blob, 7, 1)
        assert_fails(DATA_EXCEPTION) { connection.free_lob(blob) }
        assert_fails(DATA_EXCEPTION) { connection.hold_lob(clob) }
        connection.terminate
      end

      # Verifies: [CLIENT Large objects] a reader of the whole value, a chunk
      # at a time, read and readpartial as an IO's; the server sending less
      # than its length fails.
      def test_reader
        connection, server = scripted do |peer, frames|
          frames << peer.frame
          peer.reply("L", data("abcd"))
          frames << peer.frame
          peer.reply("L", data("ef"))
          frames << peer.frame
          peer.reply("L", data(""))
        end
        reader = connection.lob_reader(located(:binary, 6, 0))

        assert_equal "ab".b, reader.read(2)
        assert_equal "c".b, reader.readpartial(1, +"")
        assert_equal "def".b, reader.read
        at_the_end(reader)
        assert_fails { connection.lob_reader(located(:binary, 1, 0)).read }
        connection.terminate
        first, second = server.join

        assert_equal([Protocol::Requests.lob_read(9, 0, Lobs::CHUNK_OCTETS, characters: false),
                      Protocol::Requests.lob_read(9, 4, Lobs::CHUNK_OCTETS, characters: false)],
                     [first, second].map { Protocol::Frame.encode(*_1) })
      end

      # A reader at the end.
      def at_the_end(reader)
        assert_nil reader.read(1)
        assert_raises(EOFError) { reader.readpartial(1) }
        assert_predicate reader, :eof?
        assert_equal "", reader.read(0)
      end

      # Verifies: [PROTOCOL Lob 'L'] create of a kind, answered by a locator;
      # append of a locator's bytes, at most a chunk each, a character
      # one's cut where a character ends; free and hold answered by
      # Complete.
      def test_writer_free_and_hold
        connection, server = scripted do |peer, frames|
          frames << peer.frame
          peer.reply("L", Protocol::Writer.new.u8(1).u32(5))
          4.times do
            frames << peer.frame
            peer.complete
          end
        end
        writer = connection.create_lob(:character)
        writer << ("a" * (Lobs::CHUNK_OCTETS - 1))
        writer.write("é", "z")
        lob = writer.finish

        assert_equal [5, Lobs::CHUNK_OCTETS + 2, Lobs::CHUNK_OCTETS + 1], [lob.locator, lob.octets, lob.characters]
        assert_equal "00000", connection.hold_lob(lob).sqlstate
        assert_equal "00000", connection.free_lob(lob).sqlstate
        connection.terminate
        create, first, second, = server.join

        assert_equal Protocol::Requests.lob_create(:character), Protocol::Frame.encode(*create)
        assert_equal([Lobs::CHUNK_OCTETS - 1 + 4 + 5, 3 + 4 + 5], [first, second].map { _1.last.bytesize })
      end

      # Verifies: [CLIENT Large objects] a CLOB's octets UTF-8, a character
      # split between writes: cut where a character ends, so none is split
      # between appends; a binary one cut at the chunk.
      def test_char_cut
        assert_equal 2, Lobs.char_cut("ab\xC3\xA9".b, 3)
        assert_equal 2, Lobs.char_cut("ab\xC3".b, 9)
        assert_equal 4, Lobs.char_cut("ab\xC3\xA9".b, 9)
        assert_equal 0, Lobs.char_cut("\xF0\x9F\x98\x80".b, 3)
        assert_equal 4, Lobs.char_cut("\xF0\x9F\x98\x80".b, 4)
        assert_equal 1, Lobs.char_cut("a".b, 5)
        assert_equal 0, Lobs.char_cut("".b, 5)
        assert_equal 1, Lobs.char_cut("\x80".b, 5)
      end
    end
  end
end
