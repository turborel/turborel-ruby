# frozen_string_literal: true

module Turborel
  module Client
    # A layer of connection settings as text [CLIENT Where settings come
    # from], each named by one of KEYS, as a program, a URI, a service's
    # section or the environment gives them. Layers are laid one over
    # another, each setting taken from the first that has it.
    class Options
      # The settings' names, as the program, a URI's query and a service
      # file write them.
      KEYS = %w[
        host port user password tls_mode channel_binding application_name connect_timeout service service_file
        passfile target load_balance tls_roots tls_system_roots tls_certificate tls_key server_name
      ].freeze
      # The environment's variables, each the setting it gives.
      ENVIRONMENT = {
        "TURBOREL_HOST" => "host", "TURBOREL_PORT" => "port", "TURBOREL_USER" => "user",
        "TURBOREL_PASSWORD" => "password", "TURBOREL_TLS_MODE" => "tls_mode",
        "TURBOREL_APPLICATION_NAME" => "application_name", "TURBOREL_CONNECT_TIMEOUT" => "connect_timeout",
        "TURBOREL_SERVICE" => "service", "TURBOREL_SERVICE_FILE" => "service_file", "TURBOREL_PASSFILE" => "passfile"
      }.freeze

      # No settings, or those of +values+, a Hash of names and texts.
      #
      # @param values [Hash{String => String}]
      # @raise [Error] SQLSTATE 08001 of a name of no setting
      def initialize(values = {})
        @values = {}
        values.each { |key, value| set(key, value) }
      end

      # The settings the environment gives, +variable+ reading each of
      # ENVIRONMENT's variables, ENV's by default: one set but empty gives
      # none.
      #
      # @yieldparam name [String]
      # @yieldreturn [String, nil]
      # @return [Options]
      def self.environment(&variable)
        read = variable || ->(name) { ENV.fetch(name, nil) }
        given = ENVIRONMENT.filter_map do |name, key|
          value = read.call(name)
          [key, value] unless value.nil? || value.empty?
        end
        new(given.to_h)
      end

      # Sets +key+ to +value+.
      #
      # @param key [String]
      # @param value [String]
      # @return [Options] itself
      # @raise [Error] SQLSTATE 08001 if +key+ names no setting
      def set(key, value)
        raise Settings.invalid("#{key} is no connection setting") unless KEYS.include?(key)

        @values[key] = value.to_s
        self
      end

      # @return [String, nil] the value of +key+, if set
      def [](key) = @values[key]

      # @return [Boolean] whether none is set
      def empty? = @values.empty?

      # These settings laid over +lower+: each of +lower+'s kept where
      # these have none.
      #
      # @param lower [Options]
      # @return [Options]
      def over(lower) = Options.new(lower.to_h.merge(@values))

      # @return [Hash{String => String}] the settings, by name
      def to_h = @values.dup

      # @return [Boolean] whether +other+ sets the same
      def ==(other) = other.is_a?(Options) && other.to_h == @values

      # @return [String] the settings, never the password
      def inspect = "#<#{self.class.name} #{@values.to_h { |k, v| [k, k == "password" ? "..." : v] }}>"
    end
  end
end
