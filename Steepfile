# frozen_string_literal: true

# Steep checks lib/ against the signatures in sig/, strictly (RULES.md D6).
target :lib do
  signature "sig"
  check "lib"
  library "bigdecimal", "openssl", "socket", "zlib"
  configure_code_diagnostics(Steep::Diagnostic::Ruby.strict)
end
