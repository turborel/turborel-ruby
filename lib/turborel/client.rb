# frozen_string_literal: true

module Turborel
  # The low-level client [CLIENT Connecting]: every feature of
  # turborel-client, beneath the plain API. A connection is made to a
  # Target, TCP, a local socket or TLS, as a user a mechanism proves.
  module Client
    # Connects to the server at +target+ as +user+, proved by +mechanism+,
    # waiting as +timeouts+ say and asking for what +offer+ asks [CLIENT
    # Connecting]. Over TLS the mechanism is bound to the channel first.
    #
    # @param target [Target]
    # @param user [String]
    # @param mechanism [Mechanism]
    # @param timeouts [Timeouts]
    # @param offer [Offer]
    # @return [Connection]
    # @raise [Error] SQLSTATE 28000, before a connection is made, of a
    #   secret mechanism over plain TCP; a connection failure if none can be
    #   made, in time; the server's refusal
    def self.connect_to(target, user:, mechanism:, timeouts: DEFAULT_TIMEOUTS, offer: Offers.default)
      clear(mechanism) if target.kind == :tcp
      stream, channel = Transport.open(target, timeouts.connect)
      mechanism.bind(channel) if channel
      connection = Connection.new(stream, target, timeouts)
      connection.log_in(user, mechanism, offer)
      connection
    rescue Error
      stream&.close
      raise
    end

    # Connects to the server at +host+ and +port+ over TCP.
    #
    # @return [Connection]
    # @raise [Error] as connect_to's
    def self.connect(host, port = DEFAULT_PORT, user:, mechanism:)
      connect_to(Targets.tcp(host, port), user:, mechanism:)
    end

    # Connects to the server at the Unix socket +path+, or on Windows the
    # named pipe of that name.
    #
    # @return [Connection]
    # @raise [Error] as connect_to's
    def self.connect_local(path, user:, mechanism:)
      connect_to(Targets.local(path), user:, mechanism:)
    end

    # Refuses +mechanism+ over plain TCP if what it sends is secret
    # (SQLSTATE 28000, as the server refuses it), before anything is sent.
    #
    # @return [void]
    def self.clear(mechanism)
      return unless mechanism.secret?

      raise Error.of(Error::CONNECTION_FAILURE_SQLCODE, Error::INVALID_AUTHORIZATION_SQLSTATE,
                     "#{mechanism.name} is sent only over TLS, a Unix socket or a named pipe, never over plain TCP")
    end
  end
end
