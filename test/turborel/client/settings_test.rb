# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Turborel
  module Client
    # Connection settings: the URI, the service file, the password file,
    # the environment and the order their layers are laid in, as
    # turborel-client's own settings tests read them (RULES.md R-TEST-9).
    class SettingsTest < Minitest::Test
      include TestSupport

      UNABLE = [-919, "08001"].freeze

      # An environment of +pairs+, as Settings.resolve reads one.
      def environment(pairs = {}) = ->(name) { pairs[name] }

      def resolve(options, pairs = {}) = Settings.resolve(options, &environment(pairs))

      # A scratch file of +text+, removed after the block.
      def scratch(text)
        Dir.mktmpdir("turborel-ruby-settings") do |dir|
          path = File.join(dir, "file")
          File.write(path, text)
          yield path
        end
      end

      # Verifies: [CLIENT The connection URI] a URI gives its user, password,
      # hosts each of its port, an IPv6 address in brackets, a local socket
      # percent-encoded, and its query's settings; percent-encoding decoded
      # in each part; the password never shown.
      def test_a_uri_gives_its_user_hosts_and_settings
        uri = "turborel://ann:p%40ss@db1:7000,[::1]:7001,db3,%2Frun%2Fs.sock/?tls_mode=verify-full&target=read-write" \
              "&connect_timeout=5"
        options = Sources.uri(uri)

        assert_equal %w[ann p@ss], [options["user"], options["password"]]
        settings = resolve(options)

        assert_equal [Host.tcp("db1", 7000), Host.tcp("::1", 7001), Host.tcp("db3", DEFAULT_PORT),
                      Host.local("/run/s.sock")], settings.hosts
        assert_equal [:verify_full, :read_write, 5], [settings.tls_mode, settings.target, settings.connect_timeout]
        refute_includes "#{options.inspect} #{settings.inspect}", "p@ss"
        assert_equal [Host.tcp(Settings::DEFAULT_HOST, DEFAULT_PORT)], resolve(Sources.uri("turborel://ann@/")).hosts
      end

      # Verifies: [CLIENT The connection URI] a URI of another scheme, of a
      # path, of a key that names no setting, of a pair without =, or of a %
      # not followed by two hexadecimal digits is refused (08001); so is a
      # word no setting takes, a port that is no number, and no user.
      def test_a_malformed_uri_or_setting_is_refused
        ["other://a@b", "turborel://a@b/db", "turborel://a@b/?colour=red", "turborel://a@b/?tls_mode",
         "turborel://a%4@b", "turborel://a%ff@b"].each do |uri|
          assert_fails(UNABLE) { Sources.uri(uri) }
        end
        ["turborel://a@b/?tls_mode=always", "turborel://a@b:port", "turborel://a@b/?connect_timeout=-1",
         "turborel://b", "turborel://a@b/?connect_timeout=x", "turborel://a@b:70000"].each do |uri|
          assert_fails(UNABLE) { resolve(Sources.uri(uri)) }
        end
      end

      # Verifies: [CLIENT Where settings come from] a setting the program
      # gives prevails over the service's, which prevails over the
      # environment's, which prevails over the default; the environment
      # names the service and its file when the program does not; an empty
      # variable gives nothing.
      def test_settings_are_laid_program_service_environment_default
        text = "# servers\n[prod]\nhost = prod-db\nport = 7500\ntls_mode = require\n\n[test]\nhost = test-db\n"
        scratch(text) do |file|
          env = { "TURBOREL_SERVICE" => "prod", "TURBOREL_SERVICE_FILE" => file, "TURBOREL_USER" => "env-user",
                  "TURBOREL_PORT" => "7600", "TURBOREL_TLS_MODE" => "disable", "TURBOREL_APPLICATION_NAME" => "" }
          explicit = Options.new.set("tls_mode", "verify-ca")
          settings = resolve(explicit, env)

          assert_equal [[Host.tcp("prod-db", 7500)], :verify_ca, "env-user", nil, :prefer],
                       [settings.hosts, settings.tls_mode, settings.user, settings.application_name,
                        settings.channel_binding]
          assert_equal [Host.tcp("test-db", 7600)], resolve(explicit.set("service", "test"), env).hosts
        end
      end

      # Verifies: [CLIENT The service file] a section is its lines'
      # settings; a section that is not there, a setting before any section,
      # a line without =, a key that names no setting, and a service or
      # service file set by a service are refused, naming the file and line.
      def test_a_service_file_is_read_by_section
        options = Sources.service("[a]\nuser=ann\n[b]\nuser = bob\n  host =  h  \n", "b", "services.conf")

        assert_equal %w[bob h], [options["user"], options["host"]]
        missing = assert_fails(UNABLE) { Sources.service("[a]\nuser=ann\n", "b", "s.conf") }

        assert_match(/has no service b/, missing.message)
        { "user=ann\n" => "line 1: a setting comes before any section",
          "[a]\nuser\n" => "line 2: a setting is <key> = <value>",
          "[a]\ncolour=red\n" => "line 2: colour is no connection setting",
          "[a]\nservice=b\n" => "line 2: a service cannot set service",
          "[a\n" => "line 1: a section's name ends with ]" }.each do |text, why|
          assert_equal "services.conf #{why}", assert_fails(UNABLE) {
            Sources.service(text, "a", "services.conf")
          }.message
        end
      end

      # Verifies: [CLIENT The password file] the password of its first line
      # matching host, port and user, * matching any, \: and \\ taken as
      # they are, an escaped \* matching only *; comments and short lines
      # skipped; the settings' own password prevailing; a file that cannot
      # be read giving none.
      def test_a_password_file_matches_by_host_port_and_user
        text = "# passwords\nshort:line\ndb1:7422:ann:first\n*:*:ann:any\\:host\n" \
               "db\\:2:*:bob:c:\\\\d\n\\*:1:carl:star\n"

        assert_equal(["first", "any:host", "c:\\d", nil, "star", nil],
                     [%w[db1 7422 ann], %w[db9 1 ann], %w[db:2 7 bob], %w[x 1 carl], %w[* 1 carl], %w[db1 7422 nobody]]
                       .map { |host, port, user| Sources.password(text, host, port, user) })
        scratch(text) do |file|
          explicit = Options.new.set("user", "ann").set("passfile", file).set("host", "db1")

          assert_equal "first", resolve(explicit).password_for(Host.tcp("db1", 7422))
          assert_equal "given",
                       resolve(explicit.over(Options.new.set("password", "given"))).password_for(Host.tcp("db1", 7422))
        end
        assert_nil resolve(Options.new.set("user", "ann").set("passfile",
                                                              "/no/such/file")).password_for(Host.tcp("db1", 7422))
      end

      # Verifies: [CLIENT Where settings come from] every variable of the
      # environment gives its setting, ENV's unless a reader is given, and
      # the words of each kind are read as named.
      def test_the_environment_and_words_are_read
        options = Options.environment { "v" }

        assert(Options::ENVIRONMENT.values.all? { |key| options[key] == "v" })
        assert_kind_of Options, Options.environment
        refused = assert_fails(UNABLE) { resolve(Options.new.set("user", "u").set("target", "primary")) }

        assert_match(/any, read-write, read-only/, refused.message)
        both = resolve(Options.new("host" => "a,b", "port" => "1,2", "user" => "u", "tls_system_roots" => "true",
                                   "channel_binding" => "require", "load_balance" => "random"))

        assert_equal [[Host.tcp("a", 1), Host.tcp("b", 2)], true, :require, :random],
                     [both.hosts, both.tls.system_roots, both.channel_binding, both.load_balance]
        assert_empty Options.new
        assert_equal Options.new("user" => "u"), Options.new.set("user", "u")
        assert_fails(UNABLE) { Options.new.set("colour", "red") }
      end

      # Verifies: [CLIENT Where settings come from] a list of hosts with an
      # empty one, an IPv6 address whose bracket is not closed or whose port
      # is no number, a list of ports with one that is no number, and a word
      # no channel binding, target, load balance or truth takes are each
      # refused (08001); several hosts of one port each take it; a service
      # file that cannot be read is refused.
      def test_malformed_hosts_and_words_are_refused
        given = ->(pairs) { resolve(Options.new(pairs.merge("user" => "u"))).hosts }

        ["a,,b", "[::1", "[::1]:x"].each { |host| assert_fails(UNABLE) { given.call("host" => host) } }
        assert_fails(UNABLE) { given.call("host" => "a", "port" => "1,x") }
        %w[channel_binding target load_balance tls_system_roots].each do |key|
          assert_fails(UNABLE) { given.call(key => "sometimes") }
        end
        assert_equal [Host.tcp("a", 9), Host.tcp("b", 9), Host.tcp("::1", 9)],
                     given.call("host" => "a,b,[::1]", "port" => "9")
        assert_equal [Host.tcp("::1", 7422)], given.call("host" => "[::1]")
        assert_fails(UNABLE) { Settings.service("/no/such/service/file", "s") }
        assert_fails(UNABLE) { resolve(Options.new("user" => "u", "service" => "s", "service_file" => "/no/such")) }
      end

      # Verifies: [CLIENT The password file] a local socket matched by its
      # path and the default port.
      def test_a_password_file_matches_a_local_socket_by_its_path
        scratch("/run/s.sock:#{DEFAULT_PORT}:ann:local\n") do |file|
          settings = resolve(Options.new.set("user", "ann").set("passfile", file))

          assert_equal "local", settings.password_for(Host.local("/run/s.sock"))
        end
      end

      # Verifies: [CLIENT Where settings come from] the defaults: host
      # localhost, port 7422, tls_mode and channel_binding prefer, a connect
      # timeout of 30 seconds, 0 for none, target any, load_balance disable,
      # the service and password files in the home directory.
      def test_defaults
        settings = resolve(Options.new.set("user", "u"))

        assert_equal [[Host.tcp("localhost", 7422)], :prefer, :prefer, 30, :any, :disable, nil],
                     [settings.hosts, settings.tls_mode, settings.channel_binding, settings.connect_timeout,
                      settings.target, settings.load_balance, settings.password]
        assert_equal File.join(Dir.home, ".turborel_pass"), settings.passfile
        assert_nil resolve(Options.new.set("user", "u").set("connect_timeout", "0")).connect_timeout
        assert_kind_of KeyCache, settings.key_cache
      end
    end
  end
end
