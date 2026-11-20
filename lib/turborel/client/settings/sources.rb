# frozen_string_literal: true

module Turborel
  module Client
    # Where settings are read from beside the program: a connection URI, a
    # service file of named sections of settings, and a password file of
    # passwords by server and user [CLIENT The connection URI], [CLIENT
    # The service file], [CLIENT The password file].
    #
    # @api private
    module Sources
      # The scheme a connection URI begins with.
      SCHEME = "turborel://"
      # What begins a comment line, in either file.
      COMMENT = "#"
      # What matches any value in a password file.
      ANY = "*"
      # The fields of a password file's line.
      FIELDS = 4
      # What no service sets.
      SERVICE_KEYS = %w[service service_file].freeze

      # The settings the connection URI +uri+ gives: its user, password,
      # hosts and query, each percent-encoded (RFC 3986 §2.1).
      #
      # @param uri [String]
      # @return [Options]
      # @raise [Error] SQLSTATE 08001 if it is not one: another scheme, a
      #   path, a key of no setting, a pair without =, bad encoding
      def self.uri(uri)
        raise Settings.invalid("a connection URI begins with #{SCHEME}") unless uri.start_with?(SCHEME)

        before, _, query = uri.delete_prefix(SCHEME).partition("?")
        authority, _, path = before.partition("/")
        raise Settings.invalid("a connection URI names no database, so has no path, not /#{path}") unless path.empty?

        options = authority_options(authority)
        query.split("&").reject(&:empty?).each { |pair| query_pair(options, pair) }
        options
      end

      # The user, password and hosts of a URI's authority.
      def self.authority_options(authority)
        options = Options.new
        userinfo, at, hosts = authority.rpartition("@")
        hosts = authority if at.empty?
        user_options(options, userinfo)
        options.set("host", decode(hosts)) unless hosts.empty?
        options
      end

      # Sets the user and password of a URI's +userinfo+.
      def self.user_options(options, userinfo)
        return if userinfo.empty?

        user, colon, password = userinfo.partition(":")
        options.set("user", decode(user))
        options.set("password", decode(password)) unless colon.empty?
      end

      # Sets the setting of a query's +pair+.
      def self.query_pair(options, pair)
        key, equals, value = pair.partition("=")
        raise Settings.invalid("#{pair} in a connection URI has no =") if equals.empty?

        options.set(decode(key), decode(value))
      end

      # +text+ percent-decoded, as UTF-8.
      #
      # @raise [Error] SQLSTATE 08001 of a % not followed by two
      #   hexadecimal digits, or octets that are not UTF-8
      def self.decode(text)
        octets = text.b.gsub(/%(..)?/n) do
          digits = Regexp.last_match(1).to_s
          raise Settings.invalid("#{text} has a % without two hexadecimal digits") unless digits.match?(/\A\h\h\z/)

          [digits].pack("H2")
        end
        decoded = octets.force_encoding(Encoding::UTF_8)
        raise Settings.invalid("#{text} is not UTF-8 once decoded") unless decoded.valid_encoding?

        decoded
      end

      # The settings of the section +name+ of the service file whose text
      # is +text+, read from +file+.
      #
      # @return [Options]
      # @raise [Error] SQLSTATE 08001 if a line is malformed or sets no
      #   setting, or there is no section +name+
      def self.service(text, name, file)
        found = nil #: Options?
        section = nil #: String?
        text.each_line.with_index(1) do |raw, number|
          line = raw.strip
          next if skipped?(line)
          next section = section_name(line, file, number) if line.start_with?("[")

          option = setting(line, section, file, number)
          found = option.over(found || Options.new) if section == name
        end
        found || raise(Settings.invalid("#{file} has no service #{name}"))
      end

      # Whether +line+ is blank or a comment.
      def self.skipped?(line) = line.empty? || line.start_with?(COMMENT)

      # The name of the section +line+ begins.
      def self.section_name(line, file, number)
        raise at(file, number, "a section's name ends with ]") unless line.end_with?("]")

        line[1...-1].to_s.strip
      end

      # The setting of +line+, within +section+.
      def self.setting(line, section, file, number)
        raise at(file, number, "a setting comes before any section") unless section

        key, equals, value = line.partition("=")
        raise at(file, number, "a setting is <key> = <value>") if equals.empty?

        set_in_service(key.strip, value.strip, file, number)
      end

      # The setting +key+ of +value+ of a service, of +file+'s line
      # +number+.
      def self.set_in_service(key, value, file, number)
        raise at(file, number, "a service cannot set #{key}") if SERVICE_KEYS.include?(key)

        Options.new.set(key, value)
      rescue Error => e
        raise e if e.message.start_with?(file.to_s)

        raise at(file, number, e.message)
      end

      # The failure of +file+'s line +number+, saying +why+.
      def self.at(file, number, why) = Settings.invalid("#{file} line #{number}: #{why}")

      # The password the password file +text+ gives +user+ at +host+ and
      # +port+: that of its first line matching all three.
      #
      # @return [String, nil]
      def self.password(text, host, port, user)
        text.each_line(chomp: true).each do |line|
          next if line.lstrip.start_with?(COMMENT)

          fields = fields(line)
          next unless fields.size == FIELDS

          matched = fields.first(3).zip([host, port, user]).all? { |field, wanted| matches?(field, wanted.to_s) }
          return fields.fetch(3).first if matched
        end
        nil
      end

      # The fields of a password file's line, unescaped, each its value and
      # whether it was written plain: the first three split at each colon
      # not escaped, the fourth the rest.
      def self.fields(line)
        fields = [] #: Array[[String, bool]]
        field = +""
        escaped = false
        plain = true
        line.each_char do |char|
          if escaped
            field << char
            escaped = false
            plain = false
          elsif char == "\\" then escaped = true
          elsif char == ":" && fields.size < FIELDS - 1
            fields << [field, plain]
            field = +""
            plain = true
          else field << char
          end
        end
        fields << [field, plain]
      end

      # Whether +field+ matches +wanted+: a * written plain matches
      # anything.
      def self.matches?(field, wanted)
        value, plain = field
        (plain && value == ANY) || value == wanted
      end

      # The text of the file at +path+, if it can be read and is a regular
      # file, a link followed to one; +nil+ otherwise.
      def self.regular(path)
        File.file?(path) ? File.read(path) : nil
      rescue SystemCallError, IOError
        nil
      end
    end
  end
end
