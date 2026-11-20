# frozen_string_literal: true

module Turborel
  # The ActiveRecord adapter's registration as turborel (RULES.md D2).
  module Registration
    # Registers the adapter as turborel as ActiveRecord loads, where
    # +support+, ActiveSupport, is loaded, as Rails loads it, so
    # database.yml may name it; the adapter is required only as ActiveRecord
    # connects by it.
    #
    # @param support [Module, nil] ActiveSupport, if loaded
    # @return [void]
    def self.register(support)
      return unless support

      support.on_load(:active_record) do
        ActiveRecord::ConnectionAdapters.register(
          "turborel", "ActiveRecord::ConnectionAdapters::TurborelAdapter",
          "active_record/connection_adapters/turborel_adapter"
        )
      end
    end
  end
end

Turborel::Registration.register(defined?(ActiveSupport.on_load) && ActiveSupport)
