# frozen_string_literal: true

module Turborel
  module Client
    # SQL-92's connection statements as turborel's parser reads them
    # (ISO/IEC 9075:1992 §15): CONNECT TO a server [AS a name] [USER a
    # user] or TO DEFAULT; SET CONNECTION a name or DEFAULT; DISCONNECT a
    # name, DEFAULT, ALL or CURRENT; each name a simple value
    # specification, which a client takes as a character string literal.
    #
    # @api private
    module ConnectionStatement
      # A character string literal: quotes, a quote written twice in it.
      STRING = /\A'((?:[^']|'')*)'/
      # A parameter, a variable, or a number: a value no literal string is.
      OTHER_VALUE = /\A(?:\?|:[[:alpha:]]|[0-9.])/

      # The statement +sql+ is, if a connection statement: its kind and
      # parts; +nil+ if it is another.
      #
      # @param sql [String]
      # @return [Array, nil]
      # @raise [Error] SQLCODE -102 or -103, SQLSTATE 2A000, of one that is
      #   malformed; -900, 0A000, of a variable
      def self.parse(sql)
        reader = Reader.new(sql)
        first = reader.word
        return nil unless %w[CONNECT DISCONNECT].include?(first) || (first == "SET" && reader.word == "CONNECTION")

        reader = Reader.new(sql)
        statement = statement_of(reader)
        reader.finish
        statement
      end

      # The statement +reader+ reads.
      def self.statement_of(reader)
        case reader.word
        when "CONNECT" then connect(reader)
        when "SET"
          reader.word
          [:set, reader.took?("DEFAULT") ? nil : reader.value]
        else disconnect(reader)
        end
      end

      # CONNECT, past its key word.
      def self.connect(reader)
        reader.expect("TO")
        return [:connect, nil, nil, nil] if reader.took?("DEFAULT")

        server = reader.value
        name = reader.took?("AS") ? reader.value : nil
        user = reader.took?("USER") ? reader.value : nil
        [:connect, server, name, user]
      end

      # DISCONNECT, past its key word.
      def self.disconnect(reader)
        object = %w[DEFAULT ALL CURRENT].find { |word| reader.took?(word) }
        [:disconnect, object ? object.downcase.to_sym : reader.value]
      end

      # The text of +value+, a literal's spaces trimmed; +nil+ of none.
      #
      # @raise [Error] SQLCODE -103 of a value no character string is
      def self.text(value)
        return nil if value.nil?
        return value.gsub(/\A +| +\z/, "") if value.is_a?(String)

        raise Agent.syntax_rule("a client's connection statement names by character string literals")
      end

      # +text+ as an identifier, if it is one: a regular identifier in upper
      # case, or a delimited one's body.
      def self.identifier(text)
        tokens = Import::Names.tokens(text)
        tokens.size == 1 && tokens.first.first == :identifier ? tokens.first.last : nil
      end

      # Reads a statement's words and values, a token at a time.
      class Reader
        # A reader of +sql+.
        def initialize(sql) = @rest = sql.dup

        # The next word, upper case; +nil+ if the next token is none.
        def word
          skip
          found = @rest[/\A[[:alpha:]][[:alpha:]0-9_]*/]
          return nil unless found

          @rest = @rest[found.size..].to_s
          found.upcase
        end

        # Whether the next token is the key word +word+, read if so.
        def took?(word)
          saved = @rest
          return true if self.word == word

          @rest = saved
          false
        end

        # Reads the key word +word+, or fails.
        def expect(word)
          raise Agent.syntax("expected #{word}, found #{shown}") unless took?(word)
        end

        # A simple value specification: a literal's text, or :other of a
        # value no character string is.
        def value
          skip
          if @rest.start_with?(":")
            raise Error.of(-900, "0A000",
                           "<variable specification> (embedded SQL) is not supported")
          end

          literal = STRING.match(@rest)
          return string(literal) if literal
          return other if @rest.match?(OTHER_VALUE)

          raise Agent.syntax("expected a <literal>, found #{shown}")
        end

        # Fails unless nothing is left but a semicolon.
        def finish
          skip
          @rest = @rest.delete_prefix(";")
          skip
          raise Agent.syntax("expected the end of the statement, found #{shown}") unless @rest.empty?
        end

        private

        # The literal's text, read.
        def string(literal)
          @rest = @rest[literal[0].to_s.size..].to_s
          literal[1].to_s.gsub("''", "'")
        end

        # A number or a parameter, read.
        def other
          @rest = @rest.sub(/\A(?:\?|:[[:alpha:]][[:alnum:]_]*|[0-9.]+(?:[Ee][+-]?[0-9]+)?)/, "")
          :other
        end

        # Passes over spaces and line breaks.
        def skip = @rest = @rest.sub(/\A\s+/, "")

        # The next token, as an error shows it.
        def shown
          token = @rest[/\A\S+/]
          token ? token.inspect : "the end"
        end
      end
    end
  end
end
