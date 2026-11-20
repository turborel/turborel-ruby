# frozen_string_literal: true

# The ActiveRecord adapter, registered as turborel wherever ActiveRecord is
# loaded, as Rails loads it, so database.yml may name it; it is required
# only as ActiveRecord connects by it (RULES.md D2).
if defined?(ActiveSupport.on_load)
  ActiveSupport.on_load(:active_record) do
    ActiveRecord::ConnectionAdapters.register(
      "turborel", "ActiveRecord::ConnectionAdapters::TurborelAdapter",
      "active_record/connection_adapters/turborel_adapter"
    )
  end
end
