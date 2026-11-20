# frozen_string_literal: true

module Turborel
  module Client
    # Where a server is, and how it is reached [CLIENT Connecting]: its
    # +kind+, +:tcp+, +:local+ (a Unix socket, or on Windows a named pipe)
    # or +:tls+; its +host+ and +port+ over TCP; its +path+ of a local
    # socket; and over TLS the +server_name+ its certificate is checked
    # against and the +context+, an OpenSSL::SSL::SSLContext, that trusts
    # it.
    Target = Data.define(:kind, :host, :port, :path, :server_name, :context)

    # The TCP port a server listens on unless told another [PROTOCOL The
    # Native Protocol].
    DEFAULT_PORT = 7422
    # The named pipe a server on Windows is reached at, as turborel names
    # it [CLIENT Connecting].
    DEFAULT_PIPE = "\\\\.\\pipe\\turborel"

    # The targets a connection reaches.
    module Targets
      # @param host [String] a name or an address
      # @param port [Integer]
      # @return [Target] the server at +host+ and +port+, over TCP
      def self.tcp(host, port = DEFAULT_PORT)
        Target.new(kind: :tcp, host:, port:, path: nil, server_name: nil, context: nil)
      end

      # @param path [String] a Unix socket's path, or on Windows a named
      #   pipe's name, as \\.\pipe\turborel
      # @return [Target] the server at the local socket +path+
      def self.local(path)
        Target.new(kind: :local, host: nil, port: nil, path:, server_name: nil, context: nil)
      end

      # @param host [String]
      # @param port [Integer]
      # @param server_name [String] the name its certificate is checked
      #   against
      # @param context [OpenSSL::SSL::SSLContext] what it is trusted by
      #   (TLS.context)
      # @return [Target] the server at +host+ and +port+, over TLS
      def self.tls(host, port, server_name:, context:)
        Target.new(kind: :tls, host:, port:, path: nil, server_name:, context:)
      end
    end
  end
end
