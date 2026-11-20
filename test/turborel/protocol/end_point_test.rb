# frozen_string_literal: true

require "test_helper"

module Turborel
  module Protocol
    # The channel binding tls-server-end-point.
    class EndPointTest < Minitest::Test
      def certificate(key, digest)
        cert = OpenSSL::X509::Certificate.new
        cert.version = 2
        cert.serial = 1
        cert.subject = cert.issuer = OpenSSL::X509::Name.parse("CN=t")
        cert.public_key = key
        cert.not_before = Time.at(0)
        cert.not_after = Time.at(0) + 60
        cert.sign(key, digest)
        cert.to_der
      end

      # Verifies: [PROTOCOL Mechanisms] scram-sha-256-plus by
      # tls-server-end-point binds the hash of the server's certificate by
      # the hash its signature names: SHA-256, SHA-384 or SHA-512, and
      # SHA-256 of SHA-1 [RFC 5929 §4.1].
      def test_the_hash_of_the_signature
        ec = OpenSSL::PKey::EC.generate("prime256v1")
        { "SHA256" => "SHA256", "SHA384" => "SHA384", "SHA512" => "SHA512", "SHA1" => "SHA256" }.each do |signed, bound|
          der = certificate(ec, OpenSSL::Digest.new(signed))

          assert_equal OpenSSL::Digest.digest(bound, der), EndPoint.of(der), signed
        end
      end

      # A certificate's DER of the signature algorithm +identifier+, an
      # AlgorithmIdentifier's fields: the binding reads its outer fields alone.
      def signed_by(*identifier)
        tbs = OpenSSL::ASN1::Sequence.new([OpenSSL::ASN1::Integer.new(1)])
        OpenSSL::ASN1::Sequence.new([tbs, OpenSSL::ASN1::Sequence.new(identifier), OpenSSL::ASN1::BitString.new("s")]).to_der
      end

      def oid(dotted) = OpenSSL::ASN1::ObjectId.new(dotted)

      def explicit(tag, value) = OpenSSL::ASN1::ASN1Data.new([value], tag, :CONTEXT_SPECIFIC)

      # Verifies: [PROTOCOL Mechanisms] RSA's signature binds as its hash
      # does; one of no hash, as Ed25519's, defines no binding, nor do bytes
      # that are no certificate.
      def test_rsa_and_signatures_of_no_binding
        rsa = OpenSSL::PKey::RSA.new(2048)
        der = certificate(rsa, OpenSSL::Digest.new("SHA384"))

        assert_equal OpenSSL::Digest.digest("SHA384", der), EndPoint.of(der)
        assert_nil EndPoint.of(signed_by(oid("1.3.101.112")))
        assert_nil EndPoint.of("not a certificate")
      end

      # Verifies: [PROTOCOL Mechanisms] RSASSA-PSS binds by its hash where
      # its mask is MGF1 of the same hash, by SHA-256 of its default, SHA-1,
      # and not at all where the two differ.
      def test_rsassa_pss
        sha256 = OpenSSL::ASN1::Sequence.new([oid("2.16.840.1.101.3.4.2.1")])
        mgf1 = ->(hash) { explicit(1, OpenSSL::ASN1::Sequence.new([oid(EndPoint::MGF1), hash])) }
        same = signed_by(oid(EndPoint::RSA_PSS), OpenSSL::ASN1::Sequence.new([explicit(0, sha256), mgf1.call(sha256)]))
        defaults = signed_by(oid(EndPoint::RSA_PSS), OpenSSL::ASN1::Sequence.new([]))
        differ = signed_by(oid(EndPoint::RSA_PSS), OpenSSL::ASN1::Sequence.new([explicit(0, sha256)]))
        other_mask = signed_by(oid(EndPoint::RSA_PSS),
                               OpenSSL::ASN1::Sequence.new([explicit(1,
                                                                     OpenSSL::ASN1::Sequence.new([oid("1.2.3"),
                                                                                                  sha256]))]))

        assert_equal OpenSSL::Digest.digest("SHA256", same), EndPoint.of(same)
        assert_equal OpenSSL::Digest.digest("SHA256", defaults), EndPoint.of(defaults)
        assert_nil EndPoint.of(differ)
        assert_nil EndPoint.of(other_mask)
      end
    end
  end
end
