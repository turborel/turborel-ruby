# frozen_string_literal: true

module Turborel
  module Client
    # The client's side of the mechanisms of authentication with nothing
    # to exchange [PROTOCOL Mechanisms]. A mechanism answers +name+,
    # +initial+, +answer+, +secret?+, +ready!+, +bind+ and +refused+; Scram
    # is the other.
    class Mechanism
      # @return [String] the mechanism's name, as the server knows it
      def name = raise(NotImplementedError)

      # @return [String] the bytes sent with Hello
      def initial = "".b

      # The answer to the server's challenge +challenge+.
      #
      # @param _challenge [String]
      # @return [String]
      # @raise [Error] a connection failure: it has none
      def answer(_challenge) = raise(Error.connection_failure("#{name} has no answer to a challenge"))

      # @return [Boolean] whether what it sends is secret, so a connection
      #   over plain TCP refuses it before anything is sent
      def secret? = false

      # Whether the exchange may end as the server sends Ready.
      #
      # @return [void]
      def ready!; end

      # The connection about to carry it is secured by TLS, of +channel+.
      #
      # @param _channel [TlsChannel]
      # @return [void]
      def bind(_channel); end

      # The server refused the login it proved.
      #
      # @return [void]
      def refused; end

      # Never what proves the user.
      #
      # @return [String]
      def inspect = "#<#{self.class.name}>"
    end

    # The client's side of trust: nothing to prove, so a server takes it
    # only from a client on its own machine, where SERVER.TRUST_LOCAL is ON.
    class Trust < Mechanism
      # The mechanism's name.
      NAME = "trust"

      # @return [String]
      def name = NAME
    end

    # The client's side of password: the password, sent whole, so only over
    # TLS, a Unix socket or a named pipe.
    class Password < Mechanism
      # The mechanism's name.
      NAME = "password"

      # @param password [String]
      def initialize(password)
        super()
        @password = password
      end

      # @return [String]
      def name = NAME

      # @return [String] the password's UTF-8
      def initial = Protocol::Writer.utf8(@password).b

      # @return [Boolean] true: it is the password
      def secret? = true
    end

    # The client's side of certificate: nothing sent, the certificate
    # presented over TLS proving the user its common name names.
    class Certificate < Mechanism
      # The mechanism's name.
      NAME = "certificate"

      # @return [String]
      def name = NAME
    end
  end
end
