# frozen_string_literal: true

require "test_helper"

module Turborel
  module Protocol
    # The decoders given damaged replies: each gives a reply or fails as the
    # driver's error, and nothing else, whatever the bytes.
    class DecoderFuzzTest < Minitest::Test
      include TestSupport

      # The seed every run draws its damage from, so each run makes the same
      # cases (R-TEST-5).
      SEED = 1977
      # How many damaged bodies each test tries.
      CASES = 3000

      def corpus
        json = JsonBinary.encode({ "a" => [1, BigDecimal("2.5"), "x", nil, { "b" => true }], "c" => -0.5 })
        row = writer.u32(1).u32(4).u8(25).bytes(json).u8(11).u8(1).u8(6).u32(60).i64(1)
                    .u8(13).u32(2).u32(5).u32(2).u32(6).i128(9).u8(16).u32(1).u8(21).u8(0).u32(1).u64(2).u64(1)
        failure = writer.u32(0).str("01000").str("w").flag(true).str("r").flag(true).u64(1).flag(false)
                        .u8(7).str("W").to_s
        complete = writer.u32(0).str("00000").flag(false).u8(6).u64(1).u8(17).u32(1).bytes(failure).to_s
        prepared = writer.u32(1).u32(1).flag(true).u8(16).u32(3).u8(26).u8(0).u8(2).str("S").str("X").u8(1).str("n")
                         .u8(0).u32(1).flag(true).str("C").u8(17).u32(1).str("F").u8(4).str("G").u32(1).u32(1)
                         .flag(false).to_s
        [["B".ord, row.to_s], ["E".ord, failure], ["K".ord, complete], ["P".ord, prepared]]
      end

      def damaged(body, random)
        bytes = body.dup
        case random.rand(3)
        when 0 then bytes.setbyte(random.rand(bytes.bytesize), random.rand(256))
        when 1 then bytes = bytes.byteslice(0, random.rand(bytes.bytesize)) || ""
        else bytes.insert(random.rand(bytes.bytesize + 1), random.bytes(1 + random.rand(4)))
        end
        bytes
      end

      def decoded_or_failed(kind, body)
        Replies.decode(kind, body)
        :decoded
      rescue Error => e
        assert_includes [CONNECTION_FAILURE, CORRUPT, BEYOND], [e.sqlcode, e.sqlstate]
        :failed
      end

      # Verifies: [PROTOCOL Errors and notices] a malformed reply fails the
      # connection with SQLCODE -919 and SQLSTATE 08006, and a value in it
      # that cannot be taken with -916 or -900, never with another failure,
      # whatever its bytes.
      def test_damaged_replies_fail_only_as_connection_failures
        random = Random.new(SEED)
        cases = corpus

        cases.each { |kind, body| assert_equal :decoded, decoded_or_failed(kind, body) }
        outcomes = Array.new(CASES) do
          kind, body = cases.fetch(random.rand(cases.size))
          decoded_or_failed(kind, damaged(body, random))
        end

        assert_includes outcomes, :failed
      end

      # Verifies: [PROTOCOL Values] a damaged JSON value is one that cannot
      # be taken, TB916, or past Turborel's limits, 0A000, never another
      # failure.
      def test_damaged_json_fails_only_as_a_connection_failure
        random = Random.new(SEED)
        document = JsonBinary.encode({ "k" => [1, 2.5, "s", { "x" => nil, "a" => [true, false] }],
                                       "d" => BigDecimal("1e-3") })
        CASES.times do
          JsonBinary.decode(damaged(document, random))
        rescue Error => e
          assert_includes [CORRUPT, BEYOND], [e.sqlcode, e.sqlstate]
        end
      end
    end
  end
end
