# frozen_string_literal: true

# Steep checks lib/ against the signatures in sig/, strictly (RULES.md D11).
target :lib do
  signature "sig"
  check "lib"
  library "bigdecimal", "openssl", "securerandom", "socket", "zlib"
  configure_code_diagnostics(Steep::Diagnostic::Ruby.strict)
end
