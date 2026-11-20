# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../../server/live_server"

module Turborel
  module Client
    # A client's TLS.
    class TLSTest < Minitest::Test
      include TestSupport

      # Verifies: [CLIENT Connecting] TLS trusts the authorities of a file,
      # the platform's, or both, and verifies the server's certificate and
      # name; one of neither is refused, and so is a file that holds no
      # certificate or cannot be read.
      def test_contexts
        Dir.mktmpdir do |dir|
          files = LiveServer::Certificates.write(dir)
          context = TLS.context(roots: files[:ca], platform: true)

          assert_equal OpenSSL::SSL::VERIFY_PEER, context.verify_mode
          assert context.verify_hostname
          assert_fails { TLS.context }
          assert_fails { TLS.context(roots: files[:server_key]) }
          assert_fails { TLS.context(roots: File.join(dir, "none.pem")) }
        end
      end

      # Verifies: [CLIENT Connecting] certificate: a context presenting the
      # chain of one PEM file and the key of another, both named.
      def test_presenting
        Dir.mktmpdir do |dir|
          files = LiveServer::Certificates.write(dir)
          context = TLS.context(roots: files[:ca], certificate: files[:client], key: files[:client_key])

          assert_equal "/CN=ANN", context.cert.subject.to_s
          assert_kind_of OpenSSL::PKey::EC, context.key
          assert_fails { TLS.context(roots: files[:ca], certificate: files[:client], key: files[:ca]) }
          assert_fails { TLS.context(roots: files[:ca], certificate: files[:client]) }
        end
      end

      # Verifies: [CLIENT Connecting] the platform's authorities those of
      # SSL_CERT_FILE or SSL_CERT_DIR where set, and one there at least,
      # else refused.
      def test_platform_authorities
        Dir.mktmpdir do |dir|
          files = LiveServer::Certificates.write(dir)
          empty = File.join(dir, "empty")
          Dir.mkdir(empty)
          refused = with_environment(OpenSSL::X509::DEFAULT_CERT_DIR_ENV => empty) { assert_fails { TLS.context(platform: true) } }

          assert_match(/platform's certificate authorities/, refused.message)
          with_environment(OpenSSL::X509::DEFAULT_CERT_FILE_ENV => files[:ca]) { TLS.context(platform: true) }
        end
      end

      # Runs the block with +pairs+ in ENV, put back after.
      def with_environment(pairs)
        before = ENV.slice(*pairs.keys)
        pairs.each_key { |name| ENV.delete(name) }
        ENV.update(pairs)
        yield
      ensure
        pairs.each_key { |name| ENV.delete(name) }
        ENV.update(before)
      end
    end
  end
end
