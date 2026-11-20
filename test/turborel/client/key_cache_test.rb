# frozen_string_literal: true

require "test_helper"

module Turborel
  module Client
    # The SCRAM key cache.
    class KeyCacheTest < Minitest::Test
      # Verifies: [CLIENT The SCRAM key cache] the keys a password derived
      # are kept, a later lookup of the same salt and iterations skipping the
      # derivation; its hits and misses counted.
      def test_keys_are_kept_and_counted
        cache = KeyCache.new
        first = cache.derived("pencil", "salt", 1)

        assert_equal Protocol::Scram.derived("pencil", "salt", 1), first
        assert_same first, cache.derived("pencil", "salt", 1)
        assert_equal [1, 1], cache.lookups
        assert_equal 1, cache.size
      end

      # Verifies: [CLIENT The SCRAM key cache] an entry is found by the salt,
      # the iterations and a tag of the password under the cache's own
      # secret: a wrong password, or another salt or iterations, finds
      # nothing; the cache shows neither keys nor secret.
      def test_entries_are_found_by_salt_iterations_and_password
        cache = KeyCache.new
        cache.derived("pencil", "salt", 1)
        cache.derived("wrong", "salt", 1)
        cache.derived("pencil", "other", 1)
        cache.derived("pencil", "salt", 2)

        assert_equal [0, 4], cache.lookups
        assert_equal "#<Turborel::Client::KeyCache 4 entries>", cache.inspect
      end

      # Verifies: [CLIENT The SCRAM key cache] at most 64 entries, the oldest
      # dropped first; an entry dropped when a login that used it fails;
      # every entry dropped by clear.
      def test_bounded_forgotten_and_cleared
        cache = KeyCache.new
        65.times { |n| cache.derived("p#{n}", "s", 1) }

        assert_equal KeyCache::ENTRIES, cache.size
        cache.derived("p0", "s", 1)

        assert_equal [0, 66], cache.lookups
        cache.forget("p0", "s", 1)

        assert_equal KeyCache::ENTRIES - 1, cache.size
        cache.clear

        assert_equal 0, cache.size
      end

      # Verifies: [CLIENT The SCRAM key cache] it lives in the process's
      # memory alone, safe to share across threads.
      def test_shared_across_threads
        cache = KeyCache.new
        Array.new(4) { Thread.new { cache.derived("pencil", "salt", 1) } }.each(&:join)

        assert_equal 1, cache.size
        assert_equal 4, cache.lookups.sum
      end

      # Verifies: [CLIENT The SCRAM key cache] keys two logins derived at
      # once kept once, where the first put them: the oldest still the first
      # dropped.
      def test_keys_derived_twice_kept_once
        cache = KeyCache.new
        first = cache.derived("pencil", "salt", 1)
        (2..KeyCache::ENTRIES).each { |n| cache.derived("pencil", "salt", n) }
        cache.send(:keep, cache.send(:index, "pencil", "salt", 1), Protocol::Scram.derived("pencil", "salt", 1))

        assert_equal KeyCache::ENTRIES, cache.size
        assert_same first, cache.derived("pencil", "salt", 1)
        cache.derived("pencil", "salt", KeyCache::ENTRIES + 1)

        refute_same first, cache.derived("pencil", "salt", 1)
      end
    end
  end
end
