# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    # The Turborel adapter's parts (RULES.md D2).
    module Turborel
      # The SQL of Arel's trees as Turborel reads it: OFFSET n ROWS and
      # FETCH FIRST n ROWS ONLY, not LIMIT.
      class ArelVisitor < Arel::Visitors::ToSql
        private

        # OFFSET, then FETCH FIRST, then the lock.
        def visit_Arel_Nodes_SelectOptions(node, collector)
          collector = maybe_visit node.offset, collector
          collector = maybe_visit node.limit, collector
          maybe_visit node.lock, collector
        end

        # FETCH FIRST n ROWS ONLY.
        def visit_Arel_Nodes_Limit(node, collector)
          collector << "FETCH FIRST "
          visit(node.expr, collector) << " ROWS ONLY"
        end

        # OFFSET n ROWS.
        def visit_Arel_Nodes_Offset(node, collector)
          collector << "OFFSET "
          visit(node.expr, collector) << " ROWS"
        end
      end
    end
  end
end
