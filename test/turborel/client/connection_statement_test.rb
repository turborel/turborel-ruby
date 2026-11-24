# frozen_string_literal: true

require "test_helper"

module Turborel
  module Client
    # SQL-92's connection statements as the SQL-agent reads them.
    class ConnectionStatementTest < Minitest::Test
      include TestSupport

      def parse(sql) = ConnectionStatement.parse(sql)

      # Verifies: [CLIENT The SQL-agent] CONNECT TO a server AS a name USER
      # a user, or TO DEFAULT; SET CONNECTION a name or DEFAULT; DISCONNECT
      # a name, DEFAULT, ALL or CURRENT; any other statement none of them.
      def test_connection_statements
        assert_equal [:connect, "db:7422", "one", "bob"], parse("CONNECT TO 'db:7422' AS 'one' USER 'bob';")
        assert_equal [:connect, "it's", nil, nil], parse("connect to 'it''s'")
        assert_equal [:connect, nil, nil, nil], parse("CONNECT TO DEFAULT")
        assert_equal [[:set, "one"], [:set, nil]], [parse("SET CONNECTION 'one'"), parse("SET CONNECTION DEFAULT")]
        assert_equal([%i[disconnect all], %i[disconnect current], %i[disconnect default], [:disconnect, "one"]],
                     ["ALL", "CURRENT", "DEFAULT", "'one'"].map { parse("DISCONNECT #{_1}") })
        assert_nil parse("SELECT 1")
        assert_nil parse("SET SCHEMA X")
        assert_nil parse("CONNECTION")
      end

      # Verifies: [CLIENT The SQL-agent] a connection statement malformed, or
      # naming by a value no character string literal is, refused; a
      # literal's spaces trimmed; an identifier read as SQL reads one.
      def test_malformed_statements
        assert_fails([-102, "42000"]) { parse("CONNECT 'db'") }
        assert_fails([-102, "42000"]) { parse("CONNECT TO db") }
        assert_fails([-102, "42000"]) { parse("DISCONNECT ALL now") }
        assert_fails([-900, "0A000"]) { parse("SET CONNECTION :name") }
        assert_equal :other, parse("CONNECT TO ?").at(1)
        assert_fails([-103, "42000"]) { ConnectionStatement.text(:other) }
        assert_equal ["db", nil], [ConnectionStatement.text("  db "), ConnectionStatement.text(nil)]
        assert_equal(["ONE", "two", nil], ["one", "\"two\"", "two words"].map { ConnectionStatement.identifier(_1) })
      end

      # Verifies: [CLIENT The SQL-agent] a connection statement read as
      # turborel's lexer reads it: after comments, simple and bracketed,
      # nested; a character string literal national, introduced or in parts
      # a newline separates; any other literal a value no character string
      # is; a comment that does not end refused, as a lexical error.
      def test_statements_lexed
        assert_equal [:connect, "a", nil, nil], parse("/* x /* y */ */ CONNECT TO 'a'")
        assert_equal %i[disconnect all], parse("-- why\nDISCONNECT ALL")
        assert_equal [:connect, "ab", "one", nil], parse("CONNECT TO N'ab' AS _latin1 'one'")
        assert_equal [:connect, "ab", nil, "u"], parse("CONNECT TO 'a' -- more\n  'b' USER 'u'")
        assert_fails([-102, "42000"]) { parse("CONNECT TO 'a' 'b'") }
        others = ["X'00'", "DATE '2024-01-01'", "INTERVAL -'1' DAY TO SECOND(3)", "TRUE", "-1.5E3", "?"]

        assert_equal([:other] * 6, others.map { |value| parse("SET CONNECTION #{value}").last })
        assert_fails([-102, "42000"]) { parse("SET CONNECTION INTERVAL '1' FORTNIGHT") }
        assert_fails([-101, "42000"]) { parse("-- x") }
      end

      # Verifies: [CLIENT The SQL-agent] a bracketed comment or a literal
      # that does not end refused.
      def test_unended
        assert_fails([-101, "42000"]) { parse("/* never CONNECT TO 'a'") }
        assert_fails([-102, "42000"]) { parse("CONNECT TO 'a") }
      end
    end
  end
end
