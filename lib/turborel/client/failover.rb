# frozen_string_literal: true

require "socket"

module Turborel
  module Client
    # What a server is to a connection's session [CLIENT Several servers]:
    # +:read_write+ if it takes changes, a server alone or its group's
    # primary; +:read_only+ if it takes none, a replica following its
    # group; +:unknown+ of a replica whose role the session cannot see.
    module Role
      # The query of a server's own role in its group.
      ROLE_QUERY = "SELECT ROLE FROM INFORMATION_SCHEMA.REPLICAS WHERE IS_SELF = 'YES'"
      # The session status of whether the server takes no changes.
      SERVER_READ_ONLY = "SERVER_READ_ONLY"
      # The SQLSTATE classes of a table that does not exist, as a server
      # alone answers ROLE_QUERY.
      NO_SUCH_TABLE = %w[2A 42].freeze
      # Each role in words.
      WORDS = { read_write: "read-write", read_only: "read-only", unknown: "of a role this session cannot see" }.freeze

      # The role of +connection+'s server, as its session sees it: as its
      # session status SERVER_READ_ONLY last told it, if the server tells
      # it; else asked, the query its own transaction.
      #
      # @param connection [Connection]
      # @return [Symbol]
      # @raise [Error] a connection failure; the query's, but of a server
      #   alone
      def self.of(connection)
        told = connection.setting(SERVER_READ_ONLY)
        return told == "YES" ? :read_only : :read_write if told

        answer(connection)
      end

      # The role the query shows.
      def self.answer(connection)
        rows = asked(connection)
        return :read_write unless rows
        return :unknown if rows.empty?

        rows.first.first.to_s.rstrip == "PRIMARY" ? :read_write : :read_only
      end

      # The rows of ROLE_QUERY, asked as its own transaction; +nil+ of a
      # server alone, which has no REPLICAS.
      def self.asked(connection)
        autocommit = connection.autocommit
        connection.autocommit = true
        begin
          queried(connection)
        ensure
          connection.autocommit = autocommit
        end
      end

      # The rows of ROLE_QUERY; +nil+ of a server alone.
      def self.queried(connection)
        outcome = connection.query(ROLE_QUERY)
        none = [] #: Array[Array[value]]
        outcome.is_a?(Rows) ? outcome.rows : none
      rescue Error => e
        raise unless NO_SUCH_TABLE.any? { |c| e.sqlstate.start_with?(c) }

        nil
      end
    end

    # Connecting as Settings say, to one of several servers [CLIENT
    # Several servers]: each host tried in the order given, or in an order
    # drawn at random for each connection, and each address a host's name
    # resolves to in turn, every step within the connect timeout. A server
    # reached, logged in to and of the role asked is kept; another is left
    # and the next tried.
    class Settings
      # A connection to the first server, of the hosts in the order the
      # settings say, that can be reached, logs the user in and is of the
      # role asked [CLIENT Connecting by settings].
      #
      # @return [Connection]
      # @raise [Error] the one server's failure, if there was one; else
      #   SQLSTATE 08001 saying why each was not kept, 28000 where the last
      #   refused the user; 28000 before any connection of a channel
      #   binding required that cannot be
      def connect
        order = load_balance == :random ? hosts.shuffle(random: Random.new) : hosts
        context = TLS.of_mode(tls_mode, tls)
        tried = [] #: Array[[String, Failure]]
        order.each do |host|
          kept = first_of(host, context, tried)
          return kept if kept
        end
        raise Settings.none_kept(tried)
      end

      # The failure of a connection none of +tried+ gave.
      #
      # @api private
      # @return [Error]
      def self.none_kept(tried)
        return Error.new(tried.first.last) if tried.size == 1

        refused = tried.last&.last&.sqlstate.to_s.start_with?("28")
        message = if tried.empty? then "no server is named"
                  else "no server was kept: #{tried.map { |at, failure| "#{at}: #{failure.message}" }.join("; ")}"
                  end
        Error.of(Error::CONNECTION_FAILURE_SQLCODE, refused ? Error::INVALID_AUTHORIZATION_SQLSTATE : UNABLE_TO_CONNECT,
                 message)
      end

      private

      # The first connection to one of +host+'s targets, each failure kept
      # in +tried+; +nil+ if none.
      def first_of(host, context, tried)
        targets(host, context).each do |label, target|
          return attempt(host, target)
        rescue Error => e
          tried << [label, e.failure]
        end
        nil
      end

      # The targets of +host+, each named: its local socket, or each address
      # its name resolves to, over TLS of +context+ if any, the server's
      # certificate of server_name, else the host's.
      def targets(host, context)
        return [[host.path.to_s, Targets.local(host.path.to_s)]] if host.local?

        server = tls.server_name || host.name.to_s
        addresses(host).map do |label, address|
          [label, address.is_a?(Error) ? address : target_of(address, host.port, server, context)]
        end
      end

      # The target of +address+ and +port+: over TLS of +context+, the
      # server's certificate of +server+, if there is a context.
      def target_of(address, port, server, context)
        at = port || DEFAULT_PORT
        context ? Targets.tls(address, at, server_name: server, context:) : Targets.tcp(address, at)
      end

      # Each address +host+'s name resolves to, named; or why none.
      def addresses(host)
        Addrinfo.getaddrinfo(host.name.to_s, host.port, nil, :STREAM).map(&:ip_address).uniq.map do |ip|
          shown = ip.include?(":") ? "[#{ip}]:#{host.port}" : "#{ip}:#{host.port}"
          ["#{host.name} (#{shown})", ip]
        end
      rescue SocketError => e
        [["#{host.name}:#{host.port}", Error.connection_failure("cannot resolve the name: #{e.message}")]]
      end

      # A connection to +host+ over +target+, logged in and of the role
      # asked; under prefer, over plain TCP if TLS cannot be begun.
      def attempt(host, target)
        raise target if target.is_a?(Error)

        timeouts = Timeouts.new(connect: connect_timeout, read: nil)
        stream, channel, reached = if tls_mode == :prefer
                                     Transport.preferring(target,
                                                          timeouts.connect)
                                   else
                                     opened(target,
                                            timeouts)
                                   end
        connection = logged_in(host, reached, [stream, channel], timeouts)
        of_role(connection)
        connection
      rescue Error
        connection ? connection.abandon : stream&.close
        raise
      end

      # A stream to +target+, its channel, and +target+.
      def opened(target, timeouts)
        stream, channel = Transport.open(target, timeouts.connect)
        [stream, channel, target]
      end

      # The connection over +opened+, a stream and its channel, logged in
      # as the user, proved as the settings say.
      def logged_in(host, target, opened, timeouts)
        stream, channel = opened
        mechanism = proof(host, target)
        Client.clear(mechanism) if target.kind == :tcp
        mechanism.bind(channel) if channel
        connection = Connection.new(stream, target, timeouts)
        connection.log_in(user, mechanism, offer)
        connection
      end

      # What proves the user at +host+ over +target+: a password by SCRAM;
      # with none, the certificate named, else trust.
      def proof(host, target)
        password = password_for(host)
        mechanism = if password then Scram.new(password, binding: channel_binding, cache: key_cache)
                    elsif tls.certificate then Certificate.new
                    else Trust.new
                    end
        if channel_binding == :require && !(mechanism.is_a?(Scram) && target.kind == :tls)
          raise Error.of(Error::CONNECTION_FAILURE_SQLCODE, Error::INVALID_AUTHORIZATION_SQLSTATE,
                         "channel binding is required: SCRAM over TLS alone binds one")
        end
        mechanism
      end

      # What a connection of the settings asks for: every capability but
      # compression, and the program's name as the attribute application.
      def offer
        name = application_name
        name ? Offers.attribute(Offers.default, APPLICATION, name) : Offers.default
      end

      # Refuses +connection+, ended, if its server is not of the role asked
      # (SQLSTATE 08001).
      def of_role(connection)
        return if target == :any

        found = Role.of(connection)
        return if found == target

        connection.abandon
        raise Settings.invalid("the server is #{Role::WORDS.fetch(found)}, and #{Role::WORDS.fetch(target)} is asked")
      end
    end
  end
end
