# frozen_string_literal: true

module Turborel
  module Client
    # Where a server is, as settings name it: a +name+ and +port+ over TCP,
    # or the +path+ of a Unix socket, on Windows a named pipe.
    Host = Data.define(:name, :port, :path)

    # Hosts made.
    class Host
      # @return [Host] a server at +name+ and +port+ over TCP
      def self.tcp(name, port) = new(name:, port:, path: nil)

      # @return [Host] a server at the local socket +path+
      def self.local(path) = new(name: nil, port: nil, path:)

      # @return [Boolean] whether it is a local socket
      def local? = !path.nil?
    end

    # The files a connection's TLS is made of: +roots+, a PEM file of the
    # authorities trusted; +system_roots+, whether the platform's are too;
    # +certificate+ and +key+, PEM files of the client's chain and key, to
    # present; +server_name+, the name the server's certificate is checked
    # against, if not the host's.
    TlsFiles = Data.define(:roots, :system_roots, :certificate, :key, :server_name)

    # How to connect, as settings from outside the program say [CLIENT
    # Connecting by settings]: read from layers of Options, the program's
    # own or a URI's, then a service's section of the service file, then
    # the environment, then the defaults, each setting taken from the first
    # layer that has it [CLIENT Where settings come from]. A password none
    # of them gives is looked up in the password file. Its connections
    # share one SCRAM key cache.
    class Settings
      # The host connected to when none is named.
      DEFAULT_HOST = "localhost"
      # The service file read when none is named, in the home directory.
      DEFAULT_SERVICE_FILE = ".turborel_service.conf"
      # The password file read when none is named, in the home directory.
      DEFAULT_PASSFILE = ".turborel_pass"
      # SQLSTATE of settings no connection can be made by: the client
      # unable to establish one.
      UNABLE_TO_CONNECT = "08001"
      # The most seconds connect_timeout gives, a u64's, as Rust reads it.
      MAX_SECONDS = 18_446_744_073_709_551_615
      # The words each setting of a few takes, by its name.
      WORDS = {
        "tls_mode" => %w[disable prefer require verify-ca verify-full],
        "channel_binding" => %w[disable prefer require], "target" => %w[any read-write read-only],
        "load_balance" => %w[disable random], "tls_system_roots" => %w[true false]
      }.freeze
      # The default of each.
      DEFAULTS = { "tls_mode" => "prefer", "channel_binding" => "prefer", "target" => "any",
                   "load_balance" => "disable", "tls_system_roots" => "false" }.freeze

      # @return [Array<Host>] the servers, tried in turn
      attr_reader :hosts
      # @return [String] the user to connect as
      attr_reader :user
      # @return [String, nil] the user's password, if given
      attr_reader :password
      # @return [Symbol] how TLS is used: +:disable+, +:prefer+,
      #   +:require+, +:verify_ca+ or +:verify_full+
      attr_reader :tls_mode
      # @return [Symbol] whether SCRAM binds its channel: +:disable+,
      #   +:prefer+ or +:require+
      attr_reader :channel_binding
      # @return [String, nil] the program's name, as it tells the server
      attr_reader :application_name
      # @return [Integer, nil] seconds each step of connecting waits; +nil+,
      #   no limit
      attr_reader :connect_timeout
      # @return [String, nil] the password file
      attr_reader :passfile
      # @return [Symbol] what a server must be: +:any+, +:read_write+ or
      #   +:read_only+
      attr_reader :target
      # @return [Symbol] whether servers are tried in order: +:disable+ or
      #   +:random+
      attr_reader :load_balance
      # @return [TlsFiles] the files TLS is made of
      attr_reader :tls
      # @return [KeyCache] the SCRAM keys of its connections
      attr_reader :key_cache

      # The settings +explicit+ gives, then the service it or the
      # environment names, then the environment, then the defaults; the
      # environment's variables read by the block, ENV's by default.
      #
      # @param explicit [Options]
      # @yieldparam name [String] a variable's name
      # @yieldreturn [String, nil]
      # @return [Settings]
      # @raise [Error] SQLSTATE 08001 if a setting cannot be read, a service
      #   named cannot be read, or no user is named
      def self.resolve(explicit = Options.new, &)
        environment = Options.environment(&)
        named = explicit.over(environment)
        service_name = named["service"]
        file = named["service_file"] || at_home(DEFAULT_SERVICE_FILE)
        service = service_name ? service(file, service_name) : Options.new
        new(explicit.over(service).over(environment))
      end

      # The settings of the connection URI +uri+, as resolve lays them.
      #
      # @param uri [String]
      # @return [Settings]
      # @raise [Error] SQLSTATE 08001, as resolve's, and of a URI that is
      #   not one
      def self.from_uri(uri, &) = resolve(Sources.uri(uri), &)

      # The settings of the section +name+ of the service file +file+.
      #
      # @return [Options]
      # @raise [Error] SQLSTATE 08001 if it cannot be read, a line is
      #   malformed, or it has no section +name+
      def self.service(file, name)
        text = begin
          File.read(file.to_s)
        rescue SystemCallError, IOError => e
          raise invalid("cannot read #{file}: #{e.message}")
        end
        Sources.service(text, name, file)
      end

      # The failure of a setting that cannot be read, or settings no
      # connection can be made by (SQLCODE -919, SQLSTATE 08001).
      #
      # @api private
      # @return [Error]
      def self.invalid(message) = Error.of(Error::CONNECTION_FAILURE_SQLCODE, UNABLE_TO_CONNECT, message)

      # The file +name+ in the home directory, if there is one.
      #
      # @api private
      def self.at_home(name)
        home = Dir.home
        File.join(home, name)
      rescue ArgumentError
        nil
      end

      # The settings +options+ give, laid already, the defaults for the
      # rest.
      #
      # @param options [Options]
      # @raise [Error] SQLSTATE 08001
      def initialize(options)
        @user = Settings.user_of(options)
        @hosts = Settings.hosts(options["host"] || DEFAULT_HOST, options["port"].to_s)
        @password = options["password"]
        @application_name = options["application_name"]
        @connect_timeout = Settings.seconds(options["connect_timeout"])
        @passfile = options["passfile"] || Settings.at_home(DEFAULT_PASSFILE)
        words(options)
        @tls = files(options)
        @key_cache = KeyCache.new
      end

      # The password to prove at +host+: the settings', else the password
      # file's for the host, its port and the user, if the file can be
      # read. A local socket is matched by its path and the default port.
      #
      # @param host [Host]
      # @return [String, nil]
      def password_for(host)
        return password if password

        text = passfile && Sources.regular(passfile.to_s)
        return nil unless text

        name, port = host.local? ? [host.path, DEFAULT_PORT] : [host.name, host.port]
        Sources.password(text, name.to_s, port.to_s, user)
      end

      # @return [String] the settings, never the password
      def inspect
        "#<#{self.class.name} hosts=#{hosts.inspect} user=#{user.inspect} tls_mode=#{tls_mode} target=#{target}>"
      end

      # The hosts +text+ names, each of its own port, or the port of the
      # same place in +ports+, or the one port +ports+ gives, or the
      # default.
      #
      # @api private
      # @return [Array<Host>]
      def self.hosts(text, ports)
        numbers = ports.split(",").reject { |part| part.strip.empty? }.map { |part| port("port", part) }
        names = text.split(",", -1)
        (names.empty? ? [""] : names).each_with_index.map { |name, i| host(name.strip, port_at(numbers, i)) }
      end

      # The port of the +index+th host: of the same place in +numbers+, or
      # the one port they give, or the default.
      #
      # @api private
      def self.port_at(numbers, index)
        numbers.fetch(index) { numbers.size == 1 ? numbers.fetch(0) : DEFAULT_PORT }
      end

      # The user +options+ name, who must be named.
      #
      # @api private
      def self.user_of(options)
        options["user"] || raise(invalid("no user is named: by the program, a service, or TURBOREL_USER"))
      end

      # The host +name+ is: a path, of a local socket; [address] or
      # [address]:port, of IPv6; name:port; or a name, at +fallback+.
      #
      # @api private
      def self.host(name, fallback)
        raise invalid("a host of the list is empty") if name.empty?
        return Host.local(name) if name.start_with?("/", "\\")
        return bracketed(name, fallback) if name.start_with?("[")

        host_name, colon, port = name.partition(":")
        return Host.tcp(host_name, port("host", port)) if !colon.empty? && !port.include?(":")

        Host.tcp(name, fallback)
      end

      # An IPv6 address in brackets, and its port if it has one.
      #
      # @api private
      def self.bracketed(name, fallback)
        address, close, after = name[1..].to_s.partition("]")
        raise invalid("#{name} has no ]") if close.empty?

        Host.tcp(address, after.start_with?(":") ? port("host", after[1..].to_s) : fallback)
      end

      # The port +text+ is, the value of +key+.
      #
      # @api private
      def self.port(key, text)
        unsigned(text, 65_535) || raise(invalid("#{key} is #{text}, no port"))
      end

      # The unsigned whole number +text+ is, digits after an optional plus
      # sign, as Rust reads one, if it is at most +most+.
      #
      # @api private
      def self.unsigned(text, most)
        digits = text.strip
        return nil unless digits.match?(/\A\+?[0-9]+\z/)

        number = Integer(digits.delete_prefix("+"), 10)
        number if number <= most
      end

      # The seconds +text+ is, whole; +nil+ for 0, no limit; 30 if unset.
      #
      # @api private
      def self.seconds(text)
        return CONNECT_WITHIN if text.nil?

        number = unsigned(text, MAX_SECONDS)
        raise invalid("connect_timeout is #{text}, not a whole number of seconds") unless number

        number.zero? ? nil : number
      end

      private

      # The files TLS is made of, as +options+ name them.
      def files(options)
        TlsFiles.new(roots: options["tls_roots"], system_roots: word(options, "tls_system_roots").to_s == "true",
                     certificate: options["tls_certificate"], key: options["tls_key"],
                     server_name: options["server_name"])
      end

      # Reads the settings that are one of a few words.
      def words(options)
        @tls_mode = word(options, "tls_mode")
        @channel_binding = word(options, "channel_binding")
        @target = word(options, "target")
        @load_balance = word(options, "load_balance")
      end

      # The word the setting +key+ of +options+ is, as a Symbol.
      def word(options, key)
        text = options[key] || DEFAULTS.fetch(key)
        known = WORDS.fetch(key)
        raise Settings.invalid("#{key} is #{text}, not one of #{known.join(", ")}") unless known.include?(text)

        text.tr("-", "_").to_sym
      end
    end
  end
end
