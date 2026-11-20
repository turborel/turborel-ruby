# frozen_string_literal: true

# Steep checks lib/ against the signatures in sig/, strictly (RULES.md D11).
target :lib do
  signature "sig"
  check "lib"
  # The ActiveRecord adapter, and its registration, are written to
  # ActiveRecord's interfaces, which have no signatures of their own; their
  # tests check them, against a live server (RULES.md D2, R-LINT-2).
  ignore "lib/active_record", "lib/turborel/registration.rb"
  library "bigdecimal", "openssl", "securerandom", "socket", "zlib"
  configure_code_diagnostics(Steep::Diagnostic::Ruby.strict)
end
