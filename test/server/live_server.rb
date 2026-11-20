# frozen_string_literal: true

require "openssl"
require "tmpdir"

module Turborel
  # A turboreld of the live tests' own (RULES.md R-TEST-7, R-TEST-8): the
  # binary TURBOREL_TEST_SERVER names, or a container of the image it names
  # after "docker:", as docker:ghcr.io/turborel/turborel:nightly, run with
  # the host's network and the data directory mounted at its own path;
  # started once on loopback on its own
  # port and data directory, with test certificates made here, users that
  # prove themselves by SCRAM, a password or a certificate, and
  # SERVER.TRUST_LOCAL ON; stopped as the tests end. Without
  # TURBOREL_TEST_SERVER the live tests are skipped, saying why.
  module LiveServer
    # The environment variable naming the server's binary.
    BINARY = "TURBOREL_TEST_SERVER"
    # The port the live tests take, turborel-ruby's own, unless
    # TURBOREL_TEST_PORT says.
    PORT = 17_437
    # The users and their passwords: ANN owns the database.
    USERS = { "ann" => "ann's password", "bob" => "bob's password" }.freeze
    # How long the server has to start, in seconds.
    START_WITHIN = 30
    # The named pipe the server takes on Windows.
    PIPE = "\\\\.\\pipe\\turborel-ruby-test"
    # What the server says once it listens.
    LISTENING = "listening at"
    # What names an image rather than a binary.
    DOCKER = "docker:"

    # A live server that cannot be set up.
    class Failed < StandardError; end

    # Where things are.
    Running = Data.define(:dir, :port, :socket, :ca, :client_certificate, :client_key, :pid)

    # The server, started on first use; nil without TURBOREL_TEST_SERVER.
    #
    # @return [Running, nil]
    def self.running
      return nil unless ENV.fetch(BINARY, nil)

      @running ||= start
    end

    # Skips +test+ unless a server runs.
    def self.require!(test)
      test.skip("#{BINARY} names no turboreld, so the live tests are skipped") unless running
    end

    # Makes the database and starts the server.
    #
    # @return [Running]
    def self.start
      dir = Dir.mktmpdir("turborel-ruby-live")
      certificates = Certificates.write(dir)
      USERS.each { |user, password| add_user(dir, user, password) }
      port = Integer(ENV.fetch("TURBOREL_TEST_PORT", PORT.to_s), 10)
      socket = Gem.win_platform? ? PIPE : File.join(dir, "sock")
      pid = spawn_server(dir, port, socket, certificates)
      at_exit { stop(pid, dir) }
      schema(port)
      Running.new(dir:, port:, socket:, ca: certificates[:ca], client_certificate: certificates[:client],
                  client_key: certificates[:client_key], pid:)
    end

    # Makes ANN's schema, where the live tests make their tables.
    def self.schema(port)
      connection = Client.connect("127.0.0.1", port, user: "ann", mechanism: Client::Trust.new)
      connection.query("CREATE SCHEMA AUTHORIZATION ANN")
      connection.query("COMMIT")
      connection.terminate
    end

    # What each live test takes: the server, skipped without one, and
    # connections to it as ANN, each terminated after.
    module Case
      def setup = LiveServer.require!(self)

      # @return [Running]
      def server = LiveServer.running

      # @return [Client::Target] the server's TCP port on loopback
      def tcp = Client::Targets.tcp("127.0.0.1", server.port)

      # Gives the block a connection to +target+ as +user+, terminated
      # after unless it is lost.
      def connect(target = tcp, mechanism = Client::Trust.new, offer: Client::Offers.default, user: "ann")
        connection = Client.connect_to(target, user:, mechanism:, offer:)
        yield connection
      ensure
        connection&.terminate unless connection&.lost?
      end

      # An offer of every capability the default asks for but +names+.
      def without(*names)
        Client::Offers.default.with(capabilities: Client::Offers.default.capabilities - names)
      end
    end

    # Adds +user+ of +password+ to the database in +dir+, ANN its owner.
    def self.add_user(dir, user, password)
      args = command(dir, "--dir", File.join(dir, "db"), "--set", "SERVER.PASSWORD_ITERATIONS=10000",
                     "user", "add", user)
      args << "--owner" if user == "ann"
      IO.popen(args, "r+", err: File::NULL) do |io|
        io.puts(password, password)
        io.close_write
        io.read
      end
      raise Failed, "cannot add #{user}" unless Process.last_status.success?
    end

    # Starts the server and waits until it listens.
    #
    # @return [Integer] its process
    def self.spawn_server(dir, port, socket, certificates)
      log = File.join(dir, "out.txt")
      settings = { "PORT" => port, "TRUST_LOCAL" => "ON", "SOCKET" => socket, "TLS" => "ON", "LOGIN_DELAY_MS" => 0,
                   "TLS_CERTIFICATE" => certificates[:server], "TLS_KEY" => certificates[:server_key],
                   "TLS_CLIENT_CA" => certificates[:ca] }
      sets = settings.flat_map { |name, value| ["--set", "SERVER.#{name}=#{value}"] }
      pid = Process.spawn(*command(dir, "--dir", File.join(dir, "db"), *sets, "--log", File.join(dir, "server.log")),
                          out: log, err: log)
      wait_listening(pid, log)
      pid
    end

    # The command that runs turboreld with +args+: the binary itself, or a
    # container of the image named, as the user running the tests so the
    # files it writes in +dir+ are theirs, and named so it can be stopped.
    def self.command(dir, *args)
      server = ENV.fetch(BINARY)
      return [server, *args] unless server.start_with?(DOCKER)

      ["docker", "run", "--rm", "-i", "--network", "host", "--user", "#{Process.uid}:#{Process.gid}",
       "-v", "#{dir}:#{dir}", "--name", container, server.delete_prefix(DOCKER), *args]
    end

    # The name of the server's container, of this process.
    def self.container = "turborel-ruby-#{Process.pid}"

    # Waits until the server's output says it listens.
    def self.wait_listening(pid, log)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + START_WITHIN
      until File.exist?(log) && File.read(log).include?(LISTENING)
        raise Failed, "turboreld did not start: #{File.read(log)}" if Process.waitpid(pid, Process::WNOHANG)
        raise Failed, "turboreld did not listen in time" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

        sleep(0.05)
      end
    end

    # Stops the server, waiting on its own process, and removes its files.
    def self.stop(pid, dir)
      if ENV.fetch(BINARY).start_with?(DOCKER)
        system("docker", "kill", container, out: File::NULL, err: File::NULL)
      else
        Process.kill(Gem.win_platform? ? :KILL : :TERM, pid)
      end
      Process.wait(pid)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    ensure
      FileUtils.remove_entry(dir, true)
    end

    # The test certificates, made at each run so no secret is committed: an
    # authority, the server's for localhost and 127.0.0.1, and a client's
    # whose common name is ANN.
    module Certificates
      # How long they last, in seconds.
      LIFETIME = 24 * 60 * 60

      # Writes the certificates and keys into +dir+.
      #
      # @return [Hash{Symbol => String}] their paths
      def self.write(dir)
        ca_key = OpenSSL::PKey::EC.generate("prime256v1")
        ca = certificate("CN=turborel-ruby test authority", ca_key, [nil, ca_key], authority: true)
        server_key = OpenSSL::PKey::EC.generate("prime256v1")
        server = certificate("CN=localhost", server_key, [ca, ca_key], names: "DNS:localhost,IP:127.0.0.1")
        client_key = OpenSSL::PKey::EC.generate("prime256v1")
        client = certificate("CN=ANN", client_key, [ca, ca_key])
        files = { ca:, server:, server_key:, client:, client_key: }
        files.to_h { |name, value| [name, save(dir, name, value)] }
      end

      # A certificate of +subject+ and +key+, signed by +issuer+'s +signer+.
      def self.certificate(subject, key, (issuer, signer), authority: false, names: nil)
        cert = OpenSSL::X509::Certificate.new
        cert.version = 2
        cert.serial = OpenSSL::BN.rand(64)
        cert.subject = OpenSSL::X509::Name.parse(subject)
        cert.issuer = issuer ? issuer.subject : cert.subject
        cert.public_key = key
        cert.not_before = Time.now - 60
        cert.not_after = Time.now + LIFETIME
        extend(cert, issuer || cert, authority, names)

        cert.sign(signer, OpenSSL::Digest.new("SHA256"))
        cert
      end

      # Its extensions: an authority's, or a leaf's with its names.
      def self.extend(cert, issuer, authority, names)
        factory = OpenSSL::X509::ExtensionFactory.new(issuer, cert)
        cert.add_extension(factory.create_extension("basicConstraints", authority ? "CA:TRUE" : "CA:FALSE", true))
        usage = authority ? "keyCertSign,cRLSign" : "digitalSignature,keyAgreement"
        cert.add_extension(factory.create_extension("keyUsage", usage, true))
        cert.add_extension(factory.create_extension("subjectAltName", names)) if names
      end

      # Writes +value+, a certificate or a key, as PEM.
      def self.save(dir, name, value)
        File.join(dir, "#{name}.pem").tap { |path| File.write(path, value.to_pem) }
      end
    end
  end
end
