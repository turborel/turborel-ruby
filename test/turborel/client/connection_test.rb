# frozen_string_literal: true

require "test_helper"
require_relative "../../support/fake_server"

module Turborel
  module Client
    # A connection, against a server of the test's own script.
    class ConnectionTest < Minitest::Test
      include TestSupport

      def connect(server, offer: Offers.default, mechanism: Trust.new, timeouts: DEFAULT_TIMEOUTS)
        Client.connect_to(server.target, user: "ann", mechanism:, offer:, timeouts:)
      end

      # Verifies: [CLIENT What a connection asks for] a connection asks for
      # every capability but compression, in Hello, unless told.
      def test_hello_asks_for_every_capability_but_compression
        server = FakeServer.new do |peer|
          kind, body = peer.frame
          peer.ready
          peer.frame
          [kind, body]
        end
        connect(server).terminate
        kind, body = server.join

        assert_equal Protocol::Requests.hello(user: "ann", mechanism: "trust", initial: "",
                                              capabilities: Protocol::Capabilities::ALL - ["compression"]),
                     Protocol::Frame.encode(kind, body)
      end

      # Verifies: [PROTOCOL Opening a connection] accepted, the server sends a
      # Status for each setting, then Ready, whose capabilities are read in
      # the table's order, those this side does not know left out.
      def test_statuses_then_ready
        server = FakeServer.new do |peer|
          peer.frame
          peer.status("SCHEMA", "S")
          peer.ready(%w[status unknown notices], authorization: "BOB")
          peer.frame
        end
        connection = connect(server)

        assert_equal "BOB", connection.authorization
        assert_equal %w[notices status], connection.granted
        assert_equal({ "SCHEMA" => "S" }, connection.settings)
        assert_equal "S", connection.setting("SCHEMA")
        connection.terminate
      end

      # Verifies: [PROTOCOL Opening a connection] each Challenge answered by
      # an Answer until Ready.
      def test_challenges_are_answered
        echo = Class.new(Mechanism) do
          define_method(:name) { "echo" }
          define_method(:answer) { |challenge| challenge.reverse }
        end
        mechanism = echo.new
        server = FakeServer.new do |peer|
          peer.frame
          peer.write(Protocol::Frame.encode("C".ord, Protocol::Writer.new.bytes("ab").to_s))
          answer = peer.frame
          peer.ready
          peer.frame
          answer
        end
        connect(server, mechanism:).terminate

        assert_equal ["A".ord, Protocol::Writer.new.bytes("ba").to_s], server.join
      end

      # Verifies: [PROTOCOL Opening a connection] refused, the server sends an
      # Error and closes: the refusal is the failure, its credentials refused
      # 28000.
      def test_refusal_is_the_failure
        server = FakeServer.new do |peer|
          peer.frame
          peer.error(-919, "28000", "the user or the password is wrong")
        end
        error = assert_fails([-919, "28000"]) { connect(server) }

        assert_equal "the user or the password is wrong", error.message
      end

      # Verifies: [PROTOCOL Error 'E'] an Error of class 08 but 08003, or of
      # class 28 as the connection is made, ends the connection.
      def test_errors_that_end_the_connection
        failure = lambda { |code, state|
          Failure.new(sqlcode: code, sqlstate: state, message: "", rule: nil, position: nil, active: false,
                      diagnostics: nil)
        }

        assert Wire.ends_connection?(failure.call(-919, "08006"))
        refute Wire.ends_connection?(failure.call(-919, "08003"))
        assert Wire.ends_connection?(failure.call(-919, "28000"))
        refute Wire.ends_connection?(failure.call(-104, "28000"))
        refute Wire.ends_connection?(failure.call(-103, "42000"))
      end

      # Verifies: [PROTOCOL Opening a connection] a server that sends no Ready
      # loses the connection.
      def test_no_ready_loses_the_connection
        server = FakeServer.new do |peer|
          peer.frame
          peer.write(Protocol::Frame.encode("S".ord, ""))
        end

        assert_fails { connect(server) }
      end

      # Verifies: [PROTOCOL Compressed frames] a z frame received where
      # compression was not granted fails the connection.
      def test_z_frame_without_the_grant_fails
        server = FakeServer.new do |peer|
          peer.frame
          ready = Protocol::Writer.new.str("ANN").raw("\x07" * 16).strs([]).str("t").to_s
          peer.write(Protocol::Compression.compress_frames(Protocol::Frame.encode("R".ord, ready + (" " * 2000)), 0))
        end

        assert_fails { connect(server) }
      end

      # Verifies: [PROTOCOL Opening a connection] Ready at login is never
      # compressed; once compression is granted, a compressed reply is
      # inflated, and a request past the threshold is sent compressed.
      def test_compression_begins_after_ready
        server = FakeServer.new do |peer|
          peer.frame
          peer.ready(%w[compression])
          peer.write(Protocol::Compression.compress_frames(
                       Protocol::Frame.encode("T".ord, Protocol::Writer.new.str("A").str("x" * 3000).to_s), 0
                     ))
          peer.frame
        end
        connection = connect(server, offer: Offers.compressed(Offers.default))

        assert connection.granted?("compression")
        connection.terminate
        kind, = server.join

        assert_equal "X".ord, kind
      end

      # Verifies: [CLIENT Timeouts] each step of the login waits the connect
      # timeout; a wait that runs out loses the connection (08006), saying
      # the server did not answer in time.
      def test_login_waits_the_connect_timeout
        server = FakeServer.new { |peer| peer.frame && peer.rest }
        error = assert_fails { connect(server, timeouts: Timeouts.new(connect: 0.05, read: nil)) }

        assert_match(/did not answer in time/, error.message)
        server.join
      end

      # Verifies: [CLIENT Timeouts] the read timeout, none by default, bounds
      # each read after the login, and the program may change it.
      def test_read_timeout
        server = FakeServer.new do |peer|
          peer.frame
          peer.ready
          peer.rest
        end
        connection = connect(server)

        assert_nil connection.read_timeout
        connection.read_timeout = 0.05

        assert_in_delta 0.05, connection.read_timeout
        assert_fails { connection.send(:receive) }
        assert_predicate connection, :lost?
        server.join
      end

      # Verifies: [CLIENT Timeouts] replies taken up to 16 MiB, or as many
      # bytes as the program says; a longer one loses the connection.
      def test_longest_reply_taken
        server = FakeServer.new do |peer|
          peer.frame
          peer.ready
          peer.status("A", "x" * 100)
          peer.rest
        end
        connection = connect(server)

        assert_equal Protocol::Frame::MAX_BODY, connection.max_body
        connection.max_body = 10
        assert_fails { connection.send(:receive) }
        server.join
      end

      # Verifies: [CLIENT Connecting] terminate ends the session, a failing
      # commit's failure given; the connection takes no more after.
      def test_terminate_gives_a_failing_commit
        server = FakeServer.new do |peer|
          peer.frame
          peer.ready
          peer.frame
          peer.error(-913, "40002", "a deferred constraint is not satisfied")
        end
        connection = connect(server)

        assert_fails([-913, "40002"]) { connection.terminate }
        assert_predicate connection, :lost?
        assert_fails { connection.terminate }
      end

      # Verifies: [CLIENT Running statements] the canceller sends the key
      # Ready gave on a connection of its own.
      def test_canceller_sends_the_key
        cancel = FakeServer.new(&:frame)
        canceller = Canceller.new(cancel.target, "\x07" * 16)

        assert_nil canceller.cancel(1)
        assert_equal ["Z".ord, "\x07" * 16], cancel.join
        assert_equal "#<Turborel::Client::Canceller>", canceller.inspect
      end

      # Verifies: [CLIENT Connecting] password and SCRAM are refused over
      # plain TCP before anything is sent (28000), unless SCRAM is asked for
      # in the clear.
      def test_secrets_refused_over_plain_tcp
        target = Targets.tcp("127.0.0.1", 1)

        assert_fails([-919, "28000"]) { Client.connect_to(target, user: "a", mechanism: Password.new("p")) }
        assert_fails([-919, "28000"]) { Client.connect_to(target, user: "a", mechanism: Scram.new("p")) }
        assert_fails do
          Client.connect_to(target, user: "a", mechanism: Scram.new("p", clear: true),
                                    timeouts: Timeouts.new(connect: 1, read: nil))
        end
      end

      # Verifies: [PROTOCOL Ready 'R'] the cancel key is the client's secret:
      # never shown.
      def test_cancel_key_is_never_shown
        server = FakeServer.new do |peer|
          peer.frame
          peer.ready
          peer.frame
        end
        connection = connect(server)

        refute_includes connection.inspect, "\x07"
        refute_includes connection.canceller.inspect, "\x07"
        connection.terminate
      end

      # Verifies: [CLIENT Connecting] a connection over a stream the program
      # opened: bounded by its maker, so its read timeout is not set here,
      # and no canceller, as its server cannot be reached again.
      def test_a_stream_of_the_programs_own
        server = FakeServer.new do |peer|
          peer.frame
          peer.ready
          peer.frame
        end
        connection = Connection.open(TCPSocket.new("127.0.0.1", server.port), user: "ann", mechanism: Trust.new)

        assert_nil connection.read_timeout
        assert_nil connection.canceller
        assert_nil connection.target
        assert_fails { connection.read_timeout = 1 }
        connection.terminate
        server.join
      end

      # Verifies: [PROTOCOL Compressed frames] once compression is granted, a
      # compressed reply is inflated; a lost connection takes no more.
      def test_compressed_replies_are_inflated
        status = Protocol::Frame.encode("T".ord, Protocol::Writer.new.str("A").str("x" * 3000).to_s)
        server = FakeServer.new do |peer|
          peer.frame
          peer.ready(%w[compression])
          peer.write(Protocol::Compression.compress_frames(status, 0) + Protocol::Frame.encode("G".ord, "") + status)
          peer.rest
        end
        connection = connect(server, offer: Offers.compressed(Offers.default))

        assert_kind_of Protocol::Replies::Pong, connection.send(:receive)
        assert_equal "x" * 3000, connection.setting("A")
        connection.max_body = 1
        assert_fails { connection.send(:receive) }
        assert_fails { connection.send(:receive) }
        server.join
      end

      # Verifies: [CLIENT What the server tells] a session setting as the
      # server last told it, and all of them, with no round trip: a later
      # Status replacing an earlier one.
      def test_settings_as_last_told
        server = FakeServer.new do |peer|
          peer.frame
          peer.status("SCHEMA", "A")
          peer.status("SCHEMA", "B")
          peer.status("READ_ONLY", "NO")
          peer.ready
          peer.frame
        end
        connection = connect(server)

        assert_equal "B", connection.setting("SCHEMA")
        assert_nil connection.setting("NONE")
        assert_equal({ "SCHEMA" => "B", "READ_ONLY" => "NO" }, connection.settings)
        connection.terminate
      end

      # Verifies: [PROTOCOL Terminate 'X'] after Terminate the server sends
      # nothing, a notice, a status or a Pong before it closes, or a failing
      # commit's Error; any other reply a connection failure, as the server
      # answers no Terminate; the connection lost and its stream closed even
      # as the wait for the close runs out.
      def test_terminate_takes_no_answer
        answered = FakeServer.new do |peer|
          peer.frame
          peer.ready
          peer.frame
          peer.complete
        end
        assert_fails { connect(answered).terminate }
        answered.join
        noticed = FakeServer.new do |peer|
          peer.frame
          peer.ready
          peer.frame
          peer.notice("01T01", "rolled back")
        end

        assert_nil connect(noticed).terminate
        noticed.join
      end

      # Verifies: [CLIENT Connecting] terminate waits for the server to
      # close at most the read timeout; past it the connection is lost, its
      # stream closed.
      def test_terminate_that_runs_out
        server = FakeServer.new do |peer|
          peer.frame
          peer.ready
          peer.frame
          sleep 0.3
        end
        connection = connect(server)
        connection.read_timeout = 0.05

        assert_fails { connection.terminate }
        assert_predicate connection, :lost?
        assert_predicate connection.instance_variable_get(:@stream).instance_variable_get(:@io), :closed?
        server.join
      end

      # Verifies: [PROTOCOL Query 'Q'] a query's rows broken off by Suspended
      # lose the connection, as a direct query has no cursor to suspend.
      def test_a_query_suspended_is_broken_off
        server = FakeServer.new do |peer|
          peer.frame
          peer.ready
          peer.frame
          peer.description("N")
          peer.rows([1])
          peer.reply("S")
          peer.rest
        end
        connection = connect(server)

        assert_fails { connection.query("SELECT N FROM T") }
        assert_predicate connection, :lost?
        server.join
      end
    end
  end
end
