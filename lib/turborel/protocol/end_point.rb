# frozen_string_literal: true

require "openssl"

module Turborel
  module Protocol
    # The channel binding tls-server-end-point (RFC 5929 §4): the hash of
    # the TLS server's certificate, by a hash function its signature
    # algorithm chooses, as turborel-protocol's binding computes it. A
    # signature of MD5 or SHA-1 is bound by SHA-256; of SHA-256, SHA-384 or
    # SHA-512, by that; RSASSA-PSS by its hash, where its mask's MGF1 is of
    # the same; any other, as Ed25519's, defines no binding.
    #
    # @api private
    module EndPoint
      # The signature algorithms of one hash, by object identifier, and the
      # hash that binds a certificate they sign (RFC 3279, RFC 4055, RFC
      # 5758).
      SIGNATURES = {
        "1.2.840.113549.1.1.4" => "SHA256", "1.2.840.113549.1.1.5" => "SHA256",
        "1.2.840.113549.1.1.11" => "SHA256", "1.2.840.113549.1.1.12" => "SHA384",
        "1.2.840.113549.1.1.13" => "SHA512", "1.2.840.10045.4.1" => "SHA256",
        "1.2.840.10045.4.3.2" => "SHA256", "1.2.840.10045.4.3.3" => "SHA384",
        "1.2.840.10045.4.3.4" => "SHA512"
      }.freeze
      # id-RSASSA-PSS (RFC 4055 §3.1).
      RSA_PSS = "1.2.840.113549.1.1.10"
      # id-mgf1 (RFC 4055 §2.2).
      MGF1 = "1.2.840.113549.1.1.8"
      # id-sha1 (RFC 4055 §2.1), RSASSA-PSS's hash and mask unless named.
      SHA1 = "1.3.14.3.2.26"
      # The hash functions RSASSA-PSS names, and the hash that binds a
      # certificate it signs with one (RFC 5929 §4.1).
      HASHES = { SHA1 => "SHA256", "2.16.840.1.101.3.4.2.1" => "SHA256", "2.16.840.1.101.3.4.2.2" => "SHA384",
                 "2.16.840.1.101.3.4.2.3" => "SHA512" }.freeze
      # The context tags of RSASSA-PSS-params' hash and mask (RFC 4055 §3.1).
      PSS_HASH = 0
      # (see PSS_HASH)
      PSS_MASK = 1

      # The binding of the server whose certificate, as DER, is
      # +certificate+: its hash; +nil+ if its signature algorithm defines
      # none, or it is not a certificate.
      #
      # @param certificate [String]
      # @return [String, nil]
      def self.of(certificate)
        identifier = OpenSSL::ASN1.decode(certificate).value[1]
        algorithm = identifier.value[0].oid
        hash = algorithm == RSA_PSS ? pss(identifier.value[1]) : SIGNATURES[algorithm]
        hash && OpenSSL::Digest.digest(hash, certificate)
      rescue OpenSSL::ASN1::ASN1Error, NoMethodError, TypeError
        nil
      end

      # The hash binding a certificate signed by RSASSA-PSS of +parameters+:
      # its hash function's, if its mask is MGF1 of the same.
      #
      # @return [String, nil]
      def self.pss(parameters)
        fields = parameters.value
        hash = hash_of(tagged(fields, PSS_HASH))
        HASHES[hash] if mask_hash(tagged(fields, PSS_MASK)) == hash
      end

      # The hash function an explicit hashAlgorithm names, SHA-1 unless
      # named.
      #
      # @return [String]
      def self.hash_of(field)
        return SHA1 unless field

        field.value.first.value.first.oid
      end

      # The hash of a mask's MGF1, SHA-1 unless named; +nil+ of another mask.
      #
      # @return [String, nil]
      def self.mask_hash(mask)
        return SHA1 unless mask

        function, of = mask.value.first.value
        of.value.first.oid if function.oid == MGF1
      end

      # The field of +fields+ tagged +tag+, explicitly.
      #
      # @return [OpenSSL::ASN1::ASN1Data, nil]
      def self.tagged(fields, tag) = fields.find { |field| field.tag_class == :CONTEXT_SPECIFIC && field.tag == tag }
    end
  end
end
