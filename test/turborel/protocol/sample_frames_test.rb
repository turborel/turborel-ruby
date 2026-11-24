# frozen_string_literal: true

require "test_helper"

module Turborel
  module Protocol
    # Turborel's sample frames, test/fixtures/protocol-frames.tsv, a copy of
    # its doc/client/05-protocol-frames.tsv at 5863fe65, byte for byte
    # (RULES.md D17).
    class SampleFramesTest < Minitest::Test
      include TestSupport

      FILE = File.expand_path("../../fixtures/protocol-frames.tsv", __dir__)

      Sample = Data.define(:direction, :name, :needs, :frame, :means)

      # Each sample of the file, as the page lays a line out.
      def samples
        File.readlines(FILE, chomp: true).reject { _1.start_with?("#") }.map do |line|
          direction, name, needs, hex, means = line.split("\t", -1)
          Sample.new(direction:, name:, needs: needs == "-" ? [] : needs.split(","), frame: [hex].pack("H*"), means:)
        end
      end

      def sample(name) = samples.find { _1.name == name } || flunk("no sample #{name}")

      # The kind and body of +frame+, inflated if compressed.
      def kind_and_body(frame)
        kind, length = Frame.decode_header(frame.byteslice(0, Frame::HEADER_BYTES), Frame::MAX_BODY)
        body = frame.byteslice(Frame::HEADER_BYTES, length)
        kind == Compression::COMPRESSED ? Compression.decompress(body) : [kind, body]
      end

      def decoded(name) = Replies.decode(*kind_and_body(sample(name).frame))

      def shown(value) = value.nil? ? "NULL" : Text.of(value)

      # Verifies: [PROTOCOL Sample frames] every line of the file read as the
      # page lays it out: a direction, a unique name, the capabilities it
      # needs, the whole frame in hexadecimal, its meaning; each frame
      # whole, its header's length its body's.
      def test_the_file_as_laid_out
        all = samples

        assert_equal 166, all.size
        assert_equal all.size, all.map(&:name).uniq.size
        directions = %w[client server]

        assert(all.all? { |s| directions.include?(s.direction) && !s.means.empty? })
        assert(all.all? { |s| (s.needs - Capabilities::ALL).empty? })
        assert(all.all? { |s| s.frame.byteslice(1, 4).unpack1("V") == s.frame.bytesize - Frame::HEADER_BYTES })
      end

      # The meaning of each server sample, as the driver decodes it: a reply,
      # the first row's values as Turborel shows them, or columns' names
      # and types as SQL writes them.
      SERVER = {
        "rows" => [%w[1 a], ["NULL", ""]], "rows-none" => [], "rows-empty-row" => [[]],
        "value-null" => [["NULL"]], "value-character" => [["abc"]], "value-character-empty" => [[""]],
        "value-character-utf8" => [["é€"]], "value-exact" => [["123.45"]], "value-exact-negative" => [["-1"]],
        "value-exact-largest" => [[((2**127) - 1).to_s]], "value-approximate" => [["1.5E0"]],
        "value-approximate-negative-zero" => [["-0E0"]], "value-plugin" => [["POINT (1 2)"]],
        "value-binary" => [["DEADBEEF"]], "value-binary-empty" => [[""]], "value-date" => [["2024-02-29"]],
        "value-time" => [["12:34:56.5"]], "value-time-zoned" => [["12:34:56+05:30"]],
        "value-timestamp" => [["2024-02-29 12:34:56.123456"]],
        "value-timestamp-zoned" => [["2024-02-29 12:34:56-08:00"]],
        "value-timestamp-earliest" => [["0001-01-01 00:00:00"]], "value-interval-year-month" => [["-1-02"]],
        "value-interval-day-second" => [["1 02:03:04.500000"]], "value-true" => [["TRUE"]],
        "value-false" => [["FALSE"]], "value-decfloat" => [["-1.5"]], "value-array" => [["ARRAY[1, NULL]"]],
        "value-array-empty" => [["ARRAY[]"]], "value-row" => [["ROW('x', TRUE)"]], "value-lob-character" => [["aé"]],
        "value-lob-binary" => [["00FF"]], "value-multiset" => [["MULTISET['a', 'a']"]],
        "value-structured" => [["S.SHAPE(3, NULL)"]], "value-reference" => [["REF(0102030405060708)"]],
        "value-json" => [['{"a":[1,"x"]}']], "value-json-scalars" => [['[null,true,false,-2,1.50,"",{}]']],
        "value-xml" => [["<a>&lt;</a>"]], "value-uuid" => [["00112233-4455-6677-8899-aabbccddeeff"]]
      }.freeze

      # The columns of each Description sample: name, type as written, not
      # null, the declared name if told.
      COLUMNS = {
        "description" => [["K", "NUMERIC(10,0)", true, nil], [nil, "CHARACTER VARYING(5)", false, nil]],
        "description-empty" => [], "description-character" => [["C", "CHARACTER(4)", false, nil]],
        "description-character-octets" => [["C", "CHARACTER(16 OCTETS)", false, nil]],
        "description-exact" => [["C", "NUMERIC(9,2)", false, nil]],
        "description-approximate" => [["C", "FLOAT(53)", false, nil]],
        "description-plugin-type" => [["C", "ST_GEOMETRY", false, nil]],
        "description-varying" => [["C", "CHARACTER VARYING(20)", false, nil]],
        "description-binary" => [["C", "BINARY(16)", false, nil]],
        "description-binary-varying" => [["C", "BINARY VARYING(255)", false, nil]],
        "description-date" => [["C", "DATE", false, nil]], "description-time" => [["C", "TIME(3)", false, nil]],
        "description-time-zoned" => [["C", "TIME(0) WITH TIME ZONE", false, nil]],
        "description-timestamp" => [["C", "TIMESTAMP(6)", false, nil]],
        "description-timestamp-zoned" => [["C", "TIMESTAMP(6) WITH TIME ZONE", false, nil]],
        "description-interval-year-month" => [["C", "INTERVAL YEAR(4) TO MONTH", false, nil]],
        "description-interval-day-second" => [["C", "INTERVAL DAY(2) TO SECOND(6)", false, nil]],
        "description-boolean" => [["C", "BOOLEAN", false, nil]],
        "description-decfloat" => [["C", "DECFLOAT(34)", false, nil]],
        "description-clob" => [["C", "CHARACTER LARGE OBJECT(1048576)", false, nil]],
        "description-blob" => [["C", "BINARY LARGE OBJECT(65536)", false, nil]],
        "description-json" => [["C", "JSON", false, nil]], "description-uuid" => [["C", "UUID", false, nil]],
        "description-array" => [["C", "BOOLEAN ARRAY[3]", false, nil]],
        "description-row" => [["C", "ROW(X CHARACTER VARYING(3), Y BOOLEAN)", false, nil]],
        "description-multiset" => [["C", "CHARACTER(2) MULTISET", false, nil]],
        "description-structured" => [["C", "S.SHAPE", false, nil]],
        "description-reference" => [["C", "REF(SHAPE)", false, nil]],
        "description-reference-scoped" => [["C", "REF(SHAPE) SCOPE S.SHAPES", false, nil]],
        "description-xml-document" => [["C", "XML(DOCUMENT(UNTYPED))", false, nil]],
        "description-xml-content" => [["C", "XML(CONTENT(ANY))", false, nil]],
        "description-xml-sequence" => [["C", "XML(SEQUENCE)", false, nil]],
        "description-xml-schema" => [["C", "XML(DOCUMENT(XMLSCHEMA ID S.PO NAMESPACE 'urn:po'))", false, nil]],
        "description-distinct" => [["C", "CHARACTER VARYING(4)", false, nil]],
        "description-declared-array" => [["C", "INTEGER ARRAY[3]", false, "ARRAY"]],
        "description-declared" => [%w[I INTEGER], %w[S SMALLINT], %w[B BIGINT], ["D", "DECIMAL(9,2)"], %w[R REAL],
                                   ["P", "DOUBLE PRECISION"], ["M", "S.MONEY"]]
      }.freeze

      # Verifies: [PROTOCOL Sample frames] every server frame decoded, the
      # capabilities it needs granted, to what its meaning says: its reply's
      # kind, and each value, column and field the meaning names.
      def test_server_frames_decoded
        samples.select { _1.direction == "server" }.each do |s|
          reply = Replies.decode(*kind_and_body(s.frame))
          kind = reply.class.name.split("::").last.sub("ErrorReply", "Error").sub(/\ALob\w+/, "Lob")
          meaning = s.means.delete_prefix("Compressed z, holding ")

          assert meaning.start_with?(kind), "#{s.name}: #{kind} for #{s.means}"
        end
        SERVER.each { |name, rows| assert_equal rows, decoded(name).rows.map { |row| row.map { shown(_1) } }, name }
        COLUMNS.except("description-declared").each do |name, columns|
          told = decoded(name).columns.map do |column|
            [column.name, column.type_written, column.not_null, column.declared&.name]
          end

          assert_equal columns, told, name
        end
      end

      # Verifies: [PROTOCOL Declared types] the page's table as the samples
      # hold it: INTEGER, SMALLINT, BIGINT, DECIMAL(9,2), REAL, DOUBLE
      # PRECISION, a distinct type as USER-DEFINED with its name, INTEGER
      # ARRAY[3] as ARRAY.
      # Verifies: [PROTOCOL Sample frames] the declared types, the Prepared
      # and Description replies, Complete's tail, Errors and Notices, Lob
      # replies and every Status as their meanings say.
      def test_server_frames_in_detail
        assert_equal(COLUMNS.fetch("description-declared"),
                     decoded("description-declared").columns.map { [_1.name, _1.type_written] })
        assert_equal %w[USER-DEFINED DECIMAL],
                     decoded("description-declared").columns.values_at(6, 3).map(&:type_name)
        prepared = decoded("prepared-declared")

        columns = prepared.columns.map { |column| [column.name, column.type_written, column.not_null] }

        assert_equal [1, 2, [["K", "INTEGER", true]]], [prepared.statement, prepared.parameters.size, columns]
        assert_equal [2, [], [], nil], decoded("prepared-empty").to_h.values
        called
        every = decoded("complete-every")

        assert_equal [4711, true, 3, %w[7 8], [1500, 20, 300]],
                     [every.position, every.more, every.rows, every.generated, every.time.to_h.values]
        assert_equal([["01004", true]], decoded("complete-conditions").conditions.map { [_1.sqlstate, _1.active] })
        details
        debugged
      end

      # The frame of each client sample, as the driver encodes it.
      def client_frames
        attributes = [%w[application app]]
        {
          "hello-ping" => Requests.hello(user: "ANN", mechanism: "trust", initial: "", capabilities: ["ping"]),
          "hello-none" => Requests.hello(user: "ANN", mechanism: "trust", initial: "", capabilities: []),
          "hello-every" => Requests.hello(user: "ANN", mechanism: "trust", initial: "", attributes:,
                                          capabilities: %w[status describe cursors compression declared-types]),
          "hello-attribute-longest" => Requests.hello(user: "ANN", mechanism: "trust", initial: "", capabilities: [],
                                                      attributes: [["a" * 64, "v" * 1024]]),
          "hello-attributes-most" => Requests.hello(user: "ANN", mechanism: "trust", initial: "", capabilities: [],
                                                    attributes: Array.new(32) { ["a#{_1}", ""] }),
          "hello-scram" => Requests.hello(user: "ANN", mechanism: "scram-sha-256", initial: "n,,n=,r=abc",
                                          capabilities: []),
          "answer" => Requests.answer("c=biws,r=abc,p=xyz"), "answer-empty" => Requests.answer(""),
          "cancel" => Requests.cancel("\xA5".b * 16)
        }.merge(statement_frames, other_frames, debug_frames)
      end

      # The frames of the debugger.
      def debug_frames
        {
          "debug-identify" => Requests.debug(Requests::DEBUG_IDENTIFY), "debug-attach" => Requests.debug_attach(2),
          "debug-detach" => Requests.debug(Requests::DEBUG_DETACH),
          "debug-break" => Requests.debug_break(:procedure, "ANN", "RAISE_PAY", 4, "PCT > 5"),
          "debug-clear" => Requests.debug_clear(1), "debug-breakpoints" => Requests.debug(Requests::DEBUG_BREAKPOINTS),
          "debug-resume" => Requests.debug_resume(:over), "debug-interrupt" => Requests.debug(Requests::DEBUG_INTERRUPT),
          "debug-stack" => Requests.debug(Requests::DEBUG_STACK)
        }
      end

      # The frames of statements.
      def statement_frames
        {
          "query" => Requests.query("VALUES 1", ends: true), "query-empty" => Requests.query("", ends: false),
          "query-attributes" => Requests.query("VALUES QUERY_ATTRIBUTE('trace')", ends: false,
                                                                                  attributes: [%w[trace t1]]),
          "query-multi" => Requests.query("VALUES 1; VALUES 2", ends: true, multi: true),
          "prepare" => Requests.prepare(1, "SELECT K FROM T WHERE K > ?"),
          "execute" => Requests.execute(1, [nil, "", true], rows: 2, ends: false),
          "execute-cursor" => Requests.execute(1, [], rows: 0, ends: true, tail: { attributes: [%w[a b]], cursor: 7 }),
          "fetch" => Requests.fetch(1, rows: 100), "fetch-cursor" => Requests.fetch(1, rows: 4_294_967_295, cursor: 7),
          "close" => Requests.close(1), "close-cursor" => Requests.close(1, cursor: 7),
          "deallocate" => Requests.deallocate(4_294_967_295), "terminate" => Requests.terminate,
          "describe-statement" => Requests.describe_statement(1), "describe-cursor" => Requests.describe_cursor(1, 7)
        }
      end

      # The frames of large objects, the session and copies.
      def other_frames
        {
          "lob-read" => Requests.lob_read(3, 0, 65_536, characters: true), "lob-create" => Requests.lob_create(:binary),
          "lob-append" => Requests.lob_append(4, "\xC3".b), "lob-free" => Requests.lob_free(4),
          "lob-hold" => Requests.lob_hold(3), "ping" => Requests.ping, "reset" => Requests.reset,
          "change-user" => Requests.change_user("BOB", "password", "secret"),
          "copy-in" => Requests.copy_in("S.T", %w[ID NAME], ends: true),
          "copy-in-every-column" => Requests.copy_in("T", [], ends: false),
          "copy-data" => Requests.copy_data([["1", nil], %w[2 b]]),
          "copy-end" => Requests.copy_end(abandon: false), "copy-end-abandon" => Requests.copy_end(abandon: true)
        }
      end

      # Verifies: [PROTOCOL Sample frames] every client frame the driver can
      # send encoded byte for byte as the file holds it.
      def test_client_frames_encoded
        expected = samples.select { _1.direction == "client" && _1.name != "query-compressed" }

        assert_equal expected.map(&:name).sort, client_frames.keys.sort
        expected.each { |s| assert_equal s.frame.unpack1("H*"), client_frames.fetch(s.name).unpack1("H*"), s.name }
      end

      # Verifies: [PROTOCOL Sample frames] a compressed frame's sample
      # inflated to the frame its meaning names: kind and length as the
      # meaning says; the driver's own compression of it inflating so too.
      def test_compressed_frames_inflated
        query = Requests.query("SELECT '#{"x" * 2000}' FROM T", ends: true)
        kind, body = kind_and_body(sample("query-compressed").frame)

        assert_equal [Frame.decode_header(query.byteslice(0, 5), Frame::MAX_BODY).first, query],
                     [kind, Frame.encode(kind, body)]
        assert_equal [2021, 3972], [body.bytesize, kind_and_body(sample("rows-compressed").frame).last.bytesize]
        ours = Compression.compress_frames(query, 0)

        assert_equal query, Frame.encode(*kind_and_body(ours))
      end

      private

      # The Errors, Notices, Lob replies and Statuses.
      def details
        cited = decoded("error-diagnostics").failure

        assert_equal [-803, "23505", "ISO/IEC 9075-2:2023 §11.7", 12, true, "ERROR", "T_PK"],
                     [cited.sqlcode, cited.sqlstate, cited.rule, cited.position, cited.active,
                      cited.diagnostics.severity, cited.diagnostics.constraint]
        assert_equal ["WARNING", "cut to 4"],
                     decoded("notice-diagnostics").diagnostics.to_h.values_at(:severity, :detail)
        assert_equal ["aé".b, "".b, 4],
                     [decoded("lob-data").data, decoded("lob-data-empty").data, decoded("lob-locator").locator]
        assert_equal([%w[CATALOG TURBOREL], ["STATEMENT.TIMEOUT_MS", ""]],
                     %w[status-catalog status-null].map { decoded(_1).to_h.values })
      end

      # Verifies: [PROTOCOL Parameter modes] the sample of a Prepared of a
      # CALL: tail 20 names the procedure S.P and each ?, IN of parameter 1
      # and OUT of parameter 2, each of its type, the OUT one not among the
      # statement's inputs.
      def called
        prepared = decoded("prepared-called")
        called = prepared.called

        assert_equal [3, 1, %w[S P]], [prepared.statement, prepared.parameters.size, [called.schema, called.name]]
        assert_equal([[:in, 1, "NUMERIC(10,0)"], [:out, 2, "NUMERIC(10,0)"]],
                     called.parameters.map { [_1.mode, _1.ordinal, Text::Types.written(_1.parameter.type)] })
      end

      # Verifies: [PROTOCOL Debugged 'V'] the samples of Debugged and Event
      # decoded as their meanings say: a connection's ID, a breakpoint, the
      # breakpoints, a target running, and a pause at breakpoint 1 of one
      # frame of ANN.RAISE_PAY at line 4, column 3, PCT 10, N null, cursor
      # C closed, given again by Event paused; Event timed out, cancelled
      # and ended.
      def debugged
        breakpoint = Debug::Breakpoint.new(number: 1, schema: "ANN", name: "RAISE_PAY", line: 4, condition: nil)

        assert_equal([[:connection, 2], [:breakpoint, breakpoint], [:breakpoints, [breakpoint]], [:stack, nil]],
                     %w[connection breakpoint breakpoints running].map { decoded("debugged-#{_1}").to_h.values })
        paused = decoded("debugged-stack").value
        frame = paused.frames.first

        assert_equal [:breakpoint, 1, 1], [paused.reason, paused.breakpoint, paused.frames.size]
        assert_equal [:procedure, "ANN", "RAISE_PAY", "ANN", "RAISE_PAY"], frame.origin.to_h.values
        assert_equal [true, 4, 3], [frame.visible, frame.line, frame.column]
        assert_equal([%w[PCT INTEGER] + [10], %w[N INTEGER] + [nil], ["C", false, "SELECT ID FROM STAFF"]],
                     [frame.parameters, frame.variables, frame.cursors].map { _1.first.to_h.values })
        assert_equal Debug::Event.new(kind: :paused, paused:), decoded("event-paused")
        assert_equal(%i[timed_out cancelled ended], %w[timed-out cancelled ended].map { decoded("event-#{_1}").kind })
      end
    end
  end
end
