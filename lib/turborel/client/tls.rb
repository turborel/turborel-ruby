# frozen_string_literal: true

require "openssl"

module Turborel
  module Client
    # What a TLS connection's handshake gives a mechanism to bind itself to
    # [CLIENT Connecting]: the certificate the server presented, as DER,
    # and over TLS 1.3 its keying material of tls-exporter (RFC 9266 §2);
    # each +nil+ where there is none.
    TlsChannel = Data.define(:certificate, :exporter)

    # TLS for a client [CLIENT Connecting], by Ruby's openssl: the
    # authorities trusted are those of the files it is given, and the
    # platform's only when asked; the server's certificate is checked
    # against the name connected to.
    module TLS
      # The label of the keying material tls-exporter binds (RFC 9266 §2).
      EXPORTER_LABEL = "EXPORTER-Channel-Binding"
      # Its bytes (RFC 9266 §2).
      EXPORTER_BYTES = 32
      # The protocol version that exports tls-exporter's keying material.
      TLS13 = "TLSv1.3"

      # A context trusting the certificate authorities of the PEM file
      # +roots+ and, if +platform+, the platform's, as SSL_CERT_FILE and
      # SSL_CERT_DIR name them where set; presenting the certificate chain
      # of the PEM file +certificate+ and the key of +key+, where given,
      # for the mechanism certificate [CLIENT Connecting].
      #
      # @param roots [String, nil] a PEM file of authorities
      # @param platform [Boolean] whether the platform's are trusted too
      # @param certificate [String, nil] a PEM file of a certificate chain,
      #   the client's own first
      # @param key [String, nil] a PEM file of its private key
      # @return [OpenSSL::SSL::SSLContext]
      # @raise [Error] a connection failure if a file cannot be read, or no
      #   authority is trusted
      def self.context(roots: nil, platform: false, certificate: nil, key: nil)
        context = OpenSSL::SSL::SSLContext.new
        context.verify_mode = OpenSSL::SSL::VERIFY_PEER
        context.verify_hostname = true
        context.cert_store = store(roots, platform)
        present(context, certificate, key) if certificate
        context
      rescue OpenSSL::OpenSSLError, SystemCallError, IOError => e
        raise Error.connection_failure("cannot make TLS: #{e.message}")
      end

      # The authorities trusted: one at least.
      #
      # @return [OpenSSL::X509::Store]
      def self.store(roots, platform)
        unless roots || platform
          raise Error.connection_failure("no certificate authority is trusted: name a file of them, or the platform's")
        end

        store = OpenSSL::X509::Store.new
        store.set_default_paths if platform
        authorities(roots).each { |authority| store.add_cert(authority) } if roots
        store
      end

      # The certificates of the PEM file +path+: one at least.
      #
      # @return [Array<OpenSSL::X509::Certificate>]
      def self.authorities(path)
        found = File.read(path).scan(/-----BEGIN CERTIFICATE-----.+?-----END CERTIFICATE-----/m)
        raise Error.connection_failure("#{path} holds no certificate") if found.empty?

        found.map { |pem| OpenSSL::X509::Certificate.new(String(pem)) }
      end

      # Sets +context+ to present the chain of +certificate+ and +key+.
      #
      # @return [void]
      def self.present(context, certificate, key)
        chain = authorities(certificate)
        context.cert = chain.first
        context.extra_chain_cert = chain.drop(1)
        context.key = OpenSSL::PKey.read(File.read(key || certificate))
      end

      # What the handshake of +ssl+ gives a mechanism to bind to.
      #
      # @param ssl [OpenSSL::SSL::SSLSocket]
      # @return [TlsChannel]
      def self.channel(ssl)
        exporter = ssl.export_keying_material(EXPORTER_LABEL, EXPORTER_BYTES, "") if ssl.ssl_version == TLS13
        TlsChannel.new(certificate: ssl.peer_cert&.to_der, exporter:)
      end
    end
  end
end
