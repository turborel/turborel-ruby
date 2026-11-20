# frozen_string_literal: true

module Turborel
  module Client
    # How long a connection waits on its server, in seconds; +nil+, no
    # limit [CLIENT Timeouts]: +connect+, to connect, to begin TLS and for
    # each step of the login; +read+, for each read or write after.
    Timeouts = Data.define(:connect, :read)

    # How long a connection waits to connect and for each step of its
    # login unless told: 30 seconds, turborel-client's CONNECT_WITHIN.
    CONNECT_WITHIN = 30
    # How long terminate waits for the server to close, unless the read
    # timeout says: 60 seconds, turborel-client's TERMINATE_WITHIN.
    TERMINATE_WITHIN = 60
    # How long a cancel waits for each step: 10 seconds, turborel-client's
    # CANCEL_WITHIN.
    CANCEL_WITHIN = 10
    # The timeouts unless told: CONNECT_WITHIN to connect and log in, no
    # limit after, as a statement may run as long as it must.
    DEFAULT_TIMEOUTS = Timeouts.new(connect: CONNECT_WITHIN, read: nil)
  end
end
