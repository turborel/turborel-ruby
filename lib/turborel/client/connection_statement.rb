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
      # A character string literal's quoted part: quotes, a quote written
      # twice in it.
      STRING = /\A'((?:[^']|'')*)'/
      # What begins a character string literal: a quote, N or n for a
      # national one, or an introducer naming a character set.
      CHARACTER_START = /\A(?:N(?=')|_[[:alpha:]][[:alnum:]_]*(?=\s*'))?/i
      # A literal no character string is: a binary string's start, a
      # signed number, or a truth value.
      OTHER_LITERAL = /\A(?:X(?=')|[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:E[+-]?\d+)?|(?:TRUE|FALSE|UNKNOWN)\b|\?)/i
      # The key words a datetime or interval literal begins with.
      TYPED = %w[DATE TIME TIMESTAMP INTERVAL].freeze
      # What opens and closes a bracketed comment.
      COMMENT_MARKS = %w[/* */].freeze
      # An interval qualifier's fields.
      FIELDS = %w[YEAR MONTH DAY HOUR MINUTE SECOND].freeze

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

        # A simple value specification: a character string literal's text,
        # or :other of a parameter or another literal.
        def value
          skip
          if @rest.start_with?(":")
            raise Error.of(-900, "0A000",
                           "<variable specification> (embedded SQL) is not supported")
          end
          return :other if typed?

          found = character
          return found if found
          return other if @rest.match?(OTHER_LITERAL)

          raise Agent.syntax("expected a <literal>, found #{shown}")
        end

        # A character string literal's text, if one is next.
        def character
          start = CHARACTER_START.match(@rest).to_s
          characters(start) if @rest[start.size..].to_s.lstrip.start_with?("'")
        end

        # Fails unless nothing is left but a semicolon.
        def finish
          skip
          @rest = @rest.delete_prefix(";")
          skip
          raise Agent.syntax("expected the end of the statement, found #{shown}") unless @rest.empty?
        end

        private

        # A character string literal's text, past its +start+: its quoted
        # parts, one after another where a newline separates them.
        def characters(start)
          @rest = @rest[start.size..].to_s
          skip
          parts
        end

        # Quoted parts, each after a separator with a newline, read.
        def parts
          text = +""
          loop do
            literal = STRING.match(@rest) || raise(Agent.syntax("a <character string literal> does not end"))
            text << literal[1].to_s.gsub("''", "'")
            @rest = @rest[literal[0].to_s.size..].to_s
            break unless continued?
          end
          text
        end

        # Whether another quoted part follows after a separator with a
        # newline, the separator read if so.
        def continued?
          before = @rest
          skip
          return true if before[0, before.size - @rest.size].to_s.include?("\n") && @rest.start_with?("'")

          @rest = before
          false
        end

        # Whether a datetime or interval literal is next, read if so.
        def typed?
          saved = @rest
          word = self.word
          if TYPED.include?(word) && (word != "INTERVAL" || @rest.sub!(/\A\s*[+-]/, "") || true) &&
             @rest.lstrip.start_with?("'")
            skip
            parts
            qualifier if word == "INTERVAL"
            return true
          end
          @rest = saved
          false
        end

        # An interval qualifier: a field, its precision, TO and another.
        def qualifier
          field
          field if took?("TO")
        end

        # A field of an interval qualifier and its precision, if written.
        def field
          FIELDS.find { |name| took?(name) } || raise(Agent.syntax("expected an interval's field, found #{shown}"))
          skip
          @rest = @rest.sub(/\A\(\s*\d+\s*(?:,\s*\d+\s*)?\)/, "")
        end

        # A parameter or a literal no character string is, read.
        def other
          if @rest.match?(/\AX'/i)
            @rest = @rest[1..].to_s
            parts
          else
            @rest = @rest.sub(OTHER_LITERAL, "")
          end
          :other
        end

        # Passes over separators: spaces, line breaks and comments.
        def skip
          loop do
            before = @rest
            @rest = @rest.sub(/\A\s+/, "")
            simple_comment
            bracketed_comment
            break if @rest == before
          end
        end

        # A comment, -- to a newline, read.
        def simple_comment
          return unless @rest.start_with?("--")

          ends = @rest.index("\n") || raise(Agent.lexical("a <comment> must end with a <newline>"))
          @rest = @rest[(ends + 1)..].to_s
        end

        # A bracketed comment, each /* in it opening one nested, read.
        def bracketed_comment
          return unless @rest.start_with?("/*")

          depth = 0
          at = 0
          while at < @rest.size
            pair = @rest[at, 2]
            depth += 1 if pair == "/*"
            depth -= 1 if pair == "*/"
            at += COMMENT_MARKS.include?(pair) ? 2 : 1
            next unless depth.zero?

            @rest = @rest[at..].to_s
            return
          end
          raise Agent.lexical("a <bracketed comment> must end with */")
        end

        # The next token, as an error shows it.
        def shown
          token = @rest[/\A\S+/]
          token ? token.inspect : "the end"
        end
      end
    end
  end
end
