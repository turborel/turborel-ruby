# frozen_string_literal: true

module Turborel
  module Import
    # SQL names as turborel's lexer reads them [ISO/IEC 9075:1992 §5.2,
    # §5.4]: a table's name, of up to three identifiers, written again as
    # delimited identifiers so nothing else is taken for one; a heading
    # read as the column it names.
    #
    # @api private
    module Names
      # [ISO/IEC 9075:1992 §5.2] The reserved words, turborel's KEY_WORDS:
      # none is a regular identifier.
      KEY_WORDS = %w[
        ABSOLUTE ACTION ADD ALL ALLOCATE ALTER AND ANY ARE AS ASC ASSERTION AT AUTHORIZATION AVG
        BEGIN BETWEEN BIT BIT_LENGTH BOTH BY
        CASCADE CASCADED CASE CAST CATALOG CHAR CHARACTER CHAR_LENGTH CHARACTER_LENGTH CHECK CLOSE
        COALESCE COLLATE COLLATION COLUMN COMMIT CONNECT CONNECTION CONSTRAINT CONSTRAINTS CONTINUE
        CONVERT CORRESPONDING COUNT CREATE CROSS CURRENT CURRENT_DATE CURRENT_TIME CURRENT_TIMESTAMP
        CURRENT_USER CURSOR
        DATE DAY DEALLOCATE DEC DECIMAL DECLARE DEFAULT DEFERRABLE DEFERRED DELETE DESC DESCRIBE
        DESCRIPTOR DIAGNOSTICS DISCONNECT DISTINCT DOMAIN DOUBLE DROP
        ELSE END ESCAPE EXCEPT EXCEPTION EXEC EXECUTE EXISTS EXTERNAL EXTRACT
        FALSE FETCH FIRST FLOAT FOR FOREIGN FOUND FROM FULL
        GET GLOBAL GO GOTO GRANT GROUP
        HAVING HOUR
        IDENTITY IMMEDIATE IN INDICATOR INITIALLY INNER INPUT INSENSITIVE INSERT INT INTEGER INTERSECT
        INTERVAL INTO IS ISOLATION
        JOIN
        KEY
        LANGUAGE LAST LEADING LEFT LEVEL LIKE LOCAL LOWER
        MATCH MAX MIN MINUTE MODULE MONTH
        NAMES NATIONAL NATURAL NCHAR NEXT NO NOT NULL NULLIF NUMERIC
        OCTET_LENGTH OF ON ONLY OPEN OPTION OR ORDER OUTER OUTPUT OVERLAPS
        PAD PARTIAL POSITION PRECISION PREPARE PRESERVE PRIMARY PRIOR PRIVILEGES PROCEDURE PUBLIC
        READ REAL REFERENCES RELATIVE RESTRICT REVOKE RIGHT ROLLBACK ROWS
        SCHEMA SCROLL SECOND SECTION SELECT SESSION SESSION_USER SET SIZE SMALLINT SOME SPACE SQL
        SQLCODE SQLERROR SQLSTATE SUBSTRING SUM SYSTEM_USER
        TABLE TEMPORARY THEN TIME TIMESTAMP TIMEZONE_HOUR TIMEZONE_MINUTE TO TRAILING TRANSACTION
        TRANSLATE TRANSLATION TRIM TRUE
        UNION UNIQUE UNKNOWN UPDATE UPPER USAGE USER USING
        VALUE VALUES VARCHAR VARYING VIEW
        WHEN WHENEVER WHERE WITH WORK WRITE
        YEAR
        ZONE
      ].freeze
      # [ISO/IEC 9075:1992 §5.2 SR8, SR9] The most characters of an
      # identifier, underscores of a regular one not counted.
      MAX_IDENTIFIER_LENGTH = 128
      # The most parts of a table's name: catalog, schema and table.
      MAX_NAME_PARTS = 3
      # A regular identifier: a letter, then letters, digits and
      # underscores.
      REGULAR = /\A[[:alpha:]][[:alpha:]0-9_]*/
      # What no delimited identifier holds.
      LINE_BREAKS = ["\n", "\r"].freeze
      # The tokens a heading that names a column is.
      NAMING = %i[identifier key_word].freeze
      # A separator: a space, or a line break.
      SEPARATOR = /\A(?: |\r?\n)+/

      # +text+, a table's name, as SQL text of delimited identifiers.
      #
      # @param text [String]
      # @return [String]
      # @raise [SourceError] of text that is no table's name
      def self.table_name(text)
        tokens = tokens(text)
        raise SourceError.new(nil, "[ISO/IEC 9075:1992 §5.4] #{text} is not a <table name>") unless name?(tokens)

        tokens.each_slice(2).map { |slice| delimited(slice.first&.last.to_s) }.join(".")
      end

      # Whether +tokens+ are a table's name: one to three identifiers,
      # periods between them.
      def self.name?(tokens)
        kinds = tokens.map(&:first)
        kinds.size.odd? && kinds.size <= (2 * MAX_NAME_PARTS) - 1 &&
          kinds.each_with_index.all? { |kind, i| kind == (i.even? ? :identifier : :period) }
      end

      # The column a heading named +name+ names: the identifier it is, if
      # it is one, a regular one in upper case, and so a key word; else
      # the name as written.
      #
      # @param name [String]
      # @return [String]
      def self.column_name(name)
        tokens = tokens(name)
        return name unless tokens.size == 1 && NAMING.include?(tokens.first.first)

        tokens.first.last
      end

      # +name+ as a delimited identifier, a quote in it written twice.
      def self.delimited(name) = "\"#{name.gsub('"', '""')}\""

      # The tokens of +text+ that names are made of, each a kind and its
      # name: an identifier, a key word, a period; :other for anything
      # else, which ends them.
      def self.tokens(text)
        out = [] #: Array[[Symbol, String]]
        rest = text
        loop do
          rest = rest.sub(SEPARATOR, "")
          return out if rest.empty?

          kind, name, length = token(rest)
          out << [kind, name]
          return out if kind == :other

          rest = rest[length..] || ""
        end
      end

      # The next token of +rest+, and its length.
      def self.token(rest)
        regular = rest[REGULAR]
        return regular_token(regular) if regular && !rest.match?(/\A[XxNn]'/)
        return delimited_token(rest) if rest.start_with?('"')
        return [:period, ".", 1] if rest.start_with?(".")

        [:other, "", 0]
      end

      # A regular identifier, or a key word.
      def self.regular_token(regular)
        word = regular.upcase
        return [:key_word, word, regular.size] if KEY_WORDS.include?(word)
        return [:other, "", 0] if regular.delete("_").size > MAX_IDENTIFIER_LENGTH

        [:identifier, word, regular.size]
      end

      # A delimited identifier, its case kept, a quote written twice one.
      def self.delimited_token(rest)
        name = +""
        at = 1
        while at < rest.size
          char = rest[at]
          return [:other, "", 0] if LINE_BREAKS.include?(char)

          if char == '"'
            return closed_token(name, at) unless rest[at + 1] == '"'

            at += 1
          end
          name << char.to_s
          at += 1
        end
        [:other, "", 0]
      end

      # A delimited identifier closed at +at+: none if empty or too long.
      def self.closed_token(name, at)
        return [:other, "", 0] if name.empty? || name.size > MAX_IDENTIFIER_LENGTH

        [:identifier, name, at + 1]
      end
    end
  end
end
