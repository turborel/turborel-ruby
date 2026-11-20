# frozen_string_literal: true

require "openssl"
require "securerandom"

module Turborel
  module Protocol
    # The client's side of SCRAM-SHA-256 and SCRAM-SHA-256-PLUS [PROTOCOL
    # Mechanisms] (RFC 5802, RFC 7677): its first message, its proof
    # answering the server's first, bound to its channel, and the server's
    # signature checked, so the client knows the server knew the user's
    # verifier. The proof is made from the keys a password derives, so a
    # key cache spares the slow derivation. A password is taken as its
    # UTF-8, without SASLprep, as turborel takes it.
    #
    # @api private
    class Scram
      # The mechanism's names [PROTOCOL Mechanisms].
      MECHANISM = "scram-sha-256"
      # (see MECHANISM)
      MECHANISM_PLUS = "scram-sha-256-plus"
      # The random bytes of a nonce: 144 bits, 24 characters of base 64.
      NONCE_BYTES = 18
      # The bytes of a key, a proof or a signature: SHA-256's.
      KEY_BYTES = 32
      # The hash of every key.
      DIGEST = "SHA256"
      # What ClientKey and ServerKey are the HMAC of (RFC 5802 §3).
      CLIENT_KEY = "Client Key"
      # (see CLIENT_KEY)
      SERVER_KEY = "Server Key"
      # The GS2 header of each channel binding (RFC 5802 §6, §7; RFC 5929
      # §4; RFC 9266 §2): none, able to bind but offered none, by the
      # server's certificate, by keying material.
      HEADERS = { unbound: "n,,", unoffered: "y,,", end_point: "p=tls-server-end-point,,",
                  exporter: "p=tls-exporter,," }.freeze
      # The largest iteration count, a u32's.
      MAX_ITERATIONS = 0xFFFF_FFFF
      # What a nonce is: printable ASCII but the comma (RFC 5802 §7).
      NONCE = /\A[\x21-\x2B\x2D-\x7E]+\z/

      # What a password derives under a salt and iterations: ClientKey and
      # ServerKey (RFC 5802 §3), never the password.
      Derived = Data.define(:client, :server)

      # The server's first message, read: its text, both nonces, the salt
      # and the iterations.
      ServerFirst = Data.define(:message, :both, :salt, :iterations)

      # @return [Symbol] the channel binding: +:unbound+, +:unoffered+,
      #   +:end_point+ or +:exporter+
      attr_reader :binding

      # An exchange as +user+, of the channel binding +binding+ and the
      # data it binds.
      #
      # @param user [String] the user, as client-first names it
      # @param binding [Symbol]
      # @param data [String] what the binding binds: the server
      #   certificate's hash, or the keying material
      def initialize(user = "", binding: :unbound, data: "".b)
        @user = user
        @binding = binding
        @data = data
        @stage = :begun
      end

      # @return [Boolean] whether the exchange is bound to its channel
      def bound? = %i[end_point exporter].include?(@binding)

      # @return [Boolean] whether the server proved it knew the verifier
      def verified? = @stage == :verified

      # client-first, of +nonce+, which should be new (Scram.nonce).
      #
      # @param nonce [String]
      # @return [String]
      def first(nonce)
        @bare = "n=#{saslname(@user)},r=#{nonce}"
        @nonce = nonce
        @stage = :sent
        "#{HEADERS.fetch(@binding)}#{@bare}"
      end

      # +server_first+, read and checked against this exchange.
      #
      # @param server_first [String]
      # @return [ServerFirst]
      # @raise [Error] SQLSTATE 28000 if it is out of turn, malformed, or
      #   its nonce does not extend the client's
      def read(server_first)
        raise Scram.refused("the server's first message came out of turn") unless @stage == :sent

        message = Scram.text(server_first)
        both, salt, iterations = Scram.fields(message, %w[r s i]).map(&:to_s)
        check_nonce(both.to_s)
        ServerFirst.new(message:, both: both.to_s, salt: Scram.decode(salt.to_s, "the salt"),
                        iterations: Scram.iterations(iterations.to_s))
      end

      # client-final, answering +first+ by +keys+.
      #
      # @param first [ServerFirst]
      # @param keys [Derived]
      # @return [String]
      def prove(first, keys)
        without = "c=#{Scram.encode(HEADERS.fetch(@binding) + @data)},r=#{first.both}"
        auth = "#{@bare},#{first.message},#{without}"
        proof = Scram.xor(keys.client, OpenSSL::HMAC.digest(DIGEST, Scram.sha256(keys.client), auth))
        @expected = OpenSSL::HMAC.digest(DIGEST, keys.server, auth)
        @stage = :proved
        "#{without},p=#{Scram.encode(proof)}"
      end

      # Checks +server_final+, the server's signature.
      #
      # @param server_final [String]
      # @return [void]
      # @raise [Error] SQLSTATE 28000 if it is out of turn, an error of the
      #   server's, malformed, or not the signature expected
      def verify(server_final)
        raise Scram.refused("the server's final message came out of turn") unless @stage == :proved

        message = Scram.text(server_final)
        raise Scram.refused("the server refused: #{message.delete_prefix("e=")}") if message.start_with?("e=")

        signature = Scram.decode(Scram.attribute(message, "v"), "the server's signature")
        unless signature.bytesize == KEY_BYTES && OpenSSL.fixed_length_secure_compare(signature, @expected)
          raise Scram.refused("the server did not prove it knows the user")
        end

        @stage = :verified
      end

      # The keys +password+ derives under +salt+ and +iterations+: the slow
      # step, PBKDF2's iterations.
      #
      # @return [Derived]
      def self.derived(password, salt, iterations)
        salted = OpenSSL::KDF.pbkdf2_hmac(Writer.utf8(password).b, salt:, iterations:, length: KEY_BYTES, hash: DIGEST)
        Derived.new(client: OpenSSL::HMAC.digest(DIGEST, salted, CLIENT_KEY),
                    server: OpenSSL::HMAC.digest(DIGEST, salted, SERVER_KEY))
      end

      # @return [String] a new nonce, of the system's randomness
      def self.nonce = encode(SecureRandom.random_bytes(NONCE_BYTES))

      # @return [String] +bytes+ in base 64, with no line breaks
      def self.encode(bytes) = [bytes].pack("m0")

      # @return [String] the bytes of +text+, base 64, as +what+
      # @raise [Error] SQLSTATE 28000 if it is not base 64
      def self.decode(text, what)
        # String#unpack1's type depends on its directive, which only run
        # time reads; m0 gives a String.
        _ = text.unpack1("m0")
      rescue ArgumentError
        raise refused("#{what} is not base 64")
      end

      # The values of the attributes +names+ that +message+'s fields are, in
      # order, and no more.
      #
      # @return [Array<String>]
      # @raise [Error] SQLSTATE 28000 if one is missing, another, or more
      #   follow
      def self.fields(message, names)
        fields = message.split(",", -1)
        raise refused("the server's message has more than it should") if fields.size > names.size

        names.each_with_index.map { |name, at| attribute(fields[at], name) }
      end

      # @return [String] the bytes of +a+ and +b+, exclusive-ored
      def self.xor(first, second)
        mixed = Integer(first.unpack1("H*"), 16) ^ Integer(second.unpack1("H*"), 16)
        [format("%0*x", first.bytesize * 2, mixed)].pack("H*")
      end

      # @return [String] SHA-256 of +data+
      def self.sha256(data) = OpenSSL::Digest.digest(DIGEST, data)

      # @return [String] the value of the attribute +name+ that +field+ is
      # @raise [Error] SQLSTATE 28000 if it is missing or another
      def self.attribute(field, name)
        raise refused("the attribute #{name} is missing") unless field
        raise refused("the attribute #{name} was expected, not #{field}") unless field.start_with?("#{name}=")

        field.delete_prefix("#{name}=")
      end

      # @return [Integer] the iterations of +text+, a positive u32
      # @raise [Error] SQLSTATE 28000 if they are none
      def self.iterations(text)
        count = text.match?(/\A\+?\d+\z/) ? Integer(text.delete_prefix("+"), 10) : 0
        raise refused("the iterations are no positive number") unless count.between?(1, MAX_ITERATIONS)

        count
      end

      # @return [String] +bytes+ as UTF-8
      # @raise [Error] SQLSTATE 28000 if they are not
      def self.text(bytes)
        text = bytes.dup.force_encoding(Encoding::UTF_8)
        raise refused("a message is not UTF-8") unless text.valid_encoding?

        text
      end

      # A refusal of the exchange: credentials refused (SQLSTATE 28000).
      #
      # @return [Error]
      def self.refused(why)
        Error.of(Error::CONNECTION_FAILURE_SQLCODE, Error::INVALID_AUTHORIZATION_SQLSTATE, "SCRAM: #{why}")
      end

      private

      # Checks the server's nonce extends the client's.
      def check_nonce(both)
        return if both.match?(NONCE) && both.bytesize > @nonce.bytesize && both.start_with?(@nonce)

        raise Scram.refused("the server's nonce does not extend the client's")
      end

      # +user+ as a saslname (RFC 5802 §5.1).
      def saslname(user) = user.gsub("=", "=3D").gsub(",", "=2C")
    end
  end
end
