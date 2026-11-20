# frozen_string_literal: true

module Turborel
  module Client
    # The client's side of scram-sha-256 and scram-sha-256-plus [CLIENT
    # Connecting]: the client proves it knows the password, never sending
    # it, and takes the server only once it has proved it knows the user's
    # verifier. Over TLS it binds the exchange to the connection, by
    # tls-exporter over TLS 1.3 and else by tls-server-end-point; over TLS
    # 1.2 of a certificate that defines no binding, it is scram-sha-256
    # with the header y. Its exchange overheard lets the password be
    # guessed at leisure, so over plain TCP it is refused before anything
    # is sent unless +clear+ says otherwise.
    class Scram < Mechanism
      # The channel bindings it may take: +:prefer+ binds where the
      # connection has a binding, +:disable+ binds nothing, +:require+
      # refuses to go on unbound [CLIENT TLS by mode].
      BINDINGS = %i[prefer disable require].freeze

      # The proof of +password+.
      #
      # @param password [String]
      # @param clear [Boolean] sent over plain TCP too, for a server whose
      #   SERVER.SCRAM_WITHOUT_TLS is ON
      # @param binding [Symbol] one of BINDINGS
      # @param cache [KeyCache, nil] where its keys are kept
      # @raise [Error] SQLSTATE TB910 of a binding not among BINDINGS
      def initialize(password, clear: false, binding: :prefer, cache: nil)
        super()
        raise Error.misused("#{binding.inspect} is no channel binding") unless BINDINGS.include?(binding)

        @password = password
        @clear = clear
        @binding = binding
        @cache = cache
        @channel = [:unbound, "".b]
      end

      # @return [String] scram-sha-256-plus once bound, else scram-sha-256
      def name
        %i[end_point exporter].include?(@channel.first) ? Protocol::Scram::MECHANISM_PLUS : Protocol::Scram::MECHANISM
      end

      # client-first, of a new nonce, bound as +bind+ said; the user is the
      # one Hello names, so none is given here.
      #
      # @return [String]
      def initial
        binding, data = @channel
        @channel = [:unbound, "".b]
        exchange = Protocol::Scram.new("", binding:, data:)
        @exchange = exchange
        @used = nil
        exchange.first(Protocol::Scram.nonce)
      end

      # client-final to server-first; then, to server-final, nothing, once
      # the server's signature is right. A failure forgets the keys the
      # cache gave.
      #
      # @param challenge [String]
      # @return [String]
      def answer(challenge)
        exchange = @exchange
        raise Error.connection_failure("SCRAM was not begun") unless exchange

        return "".b.tap { exchange.verify(challenge) } if challenge.start_with?("v=", "e=")

        prove(exchange, challenge)
      rescue Error
        forget
        raise
      end

      # @return [Boolean] whether it is refused over plain TCP
      def secret? = !@clear

      # Bound to +channel+'s tls-exporter, over TLS 1.3; else to its
      # certificate's tls-server-end-point; else able to bind but offered
      # none. Under +:disable+, nothing.
      #
      # @param channel [TlsChannel]
      # @return [void]
      def bind(channel)
        return if @binding == :disable

        end_point = channel.certificate && Protocol::EndPoint.of(channel.certificate)
        @channel = if channel.exporter then [:exporter, channel.exporter]
                   elsif end_point then [:end_point, end_point]
                   else [:unoffered, "".b]
                   end
      end

      # @raise [Error] a connection failure if the server has not proved it
      #   knows the user's verifier
      # @return [void]
      def ready!
        return if @exchange&.verified?

        raise Error.connection_failure("the server did not prove it knows the user's verifier")
      end

      # Forgets the keys the exchange used.
      #
      # @return [void]
      def refused = forget

      private

      # client-final, answering server-first.
      def prove(exchange, challenge)
        if @binding == :require && !exchange.bound?
          raise Protocol::Scram.refused("channel binding is required, and this connection is not bound")
        end

        first = exchange.read(challenge)
        @used = [first.salt, first.iterations]
        exchange.prove(first, keys(first))
      end

      # The keys of +first+'s salt and iterations: the cache's, or derived.
      def keys(first)
        cache = @cache
        return cache.derived(@password, first.salt, first.iterations) if cache

        Protocol::Scram.derived(@password, first.salt, first.iterations)
      end

      # Forgets the keys the exchange used, if the cache gave them.
      def forget
        used = @used
        @cache&.forget(@password, used[0], used[1]) if used
        @used = nil
      end
    end
  end
end
