# frozen_string_literal: true

require "openssl"
require "securerandom"

module Turborel
  module Client
    # The SCRAM key cache [CLIENT The SCRAM key cache]: the keys a password
    # derived under a server's salt and iterations, kept in the process's
    # memory, so a login that meets the same salt and iterations skips
    # PBKDF2, the slow step. An entry is found by the salt, the iterations
    # and a tag of the password under a random secret of the cache's own,
    # so a wrong password finds nothing and the cache holds neither the
    # password nor anything it could be guessed from offline. It holds 64
    # entries at most, the oldest dropped first, and drops an entry when a
    # login that used it fails. It is safe to share across threads.
    class KeyCache
      # The most entries a cache holds, turborel-client's KEY_CACHE_ENTRIES.
      ENTRIES = 64
      # The bytes of the secret its tags are made under.
      SECRET_BYTES = 32

      # An empty cache, its secret new.
      def initialize
        @secret = SecureRandom.random_bytes(SECRET_BYTES)
        @entries = []
        @hits = 0
        @misses = 0
        @lock = Mutex.new
      end

      # The keys +password+ derives under +salt+ and +iterations+: the
      # cache's, or derived, outside the lock, and kept.
      #
      # @param password [String]
      # @param salt [String]
      # @param iterations [Integer]
      # @return [Protocol::Scram::Derived]
      def derived(password, salt, iterations)
        index = index(password, salt, iterations)
        found = @lock.synchronize { lookup(index) }
        return found if found

        keys = Protocol::Scram.derived(password, salt, iterations)
        @lock.synchronize { keep(index, keys) }
        keys
      end

      # Drops the keys of +password+ under +salt+ and +iterations+, as an
      # exchange by them failed.
      #
      # @return [void]
      def forget(password, salt, iterations)
        index = index(password, salt, iterations)
        @lock.synchronize { @entries.reject! { |entry| entry.first == index } }
      end

      # @return [Integer] how many entries it holds
      def size = @lock.synchronize { @entries.size }

      # @return [Array(Integer, Integer)] how many lookups found their keys,
      #   and how many derived them
      def lookups = @lock.synchronize { [@hits, @misses] }

      # Drops every entry.
      #
      # @return [void]
      def clear = @lock.synchronize { @entries.clear }

      # Never the secret, nor the keys.
      #
      # @return [String]
      def inspect = "#<#{self.class.name} #{size} entries>"

      private

      # What an entry is found by.
      def index(password, salt, iterations)
        [OpenSSL::HMAC.digest(Protocol::Scram::DIGEST, @secret, Protocol::Writer.utf8(password).b), salt.b, iterations]
      end

      # The keys of +index+, counted as a hit or a miss.
      def lookup(index)
        entry = @entries.find { |held| held.first == index }
        entry ? @hits += 1 : @misses += 1
        entry&.last
      end

      # Keeps +keys+ under +index+, the oldest dropped past ENTRIES.
      def keep(index, keys)
        @entries.reject! { |held| held.first == index }
        @entries.shift if @entries.size >= ENTRIES
        @entries << [index, keys]
      end
    end
  end
end
