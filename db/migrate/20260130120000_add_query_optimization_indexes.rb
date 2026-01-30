# frozen_string_literal: true

class AddQueryOptimizationIndexes < ActiveRecord::Migration[8.1]
  def change
    # ─────────────────────────────────────────────────────────────────────────────
    # SystemEvent indexes
    # ─────────────────────────────────────────────────────────────────────────────
    #
    # Already have: (kind, occurred_at), (status, occurred_at)
    # Adding: standalone occurred_at for date range queries, and payload GIN for JSONB search

    # Standalone occurred_at index for date range queries (today, last_24_hours, etc.)
    add_index :system_events, :occurred_at, name: "index_system_events_on_occurred_at"

    # GIN index on payload for JSONB containment queries and text search
    # This optimizes queries like: payload ->> 'gem_name' = ?
    add_index :system_events, :payload, using: :gin, name: "index_system_events_on_payload_gin"

    # ─────────────────────────────────────────────────────────────────────────────
    # Advisory indexes
    # ─────────────────────────────────────────────────────────────────────────────
    #
    # Already have: fingerprint (unique), gem_name
    # Adding: severity, published_at, source, and composite for common queries

    add_index :advisories, :severity, name: "index_advisories_on_severity"
    add_index :advisories, :published_at, name: "index_advisories_on_published_at"
    add_index :advisories, :source, name: "index_advisories_on_source"

    # Composite index for common filtering: active advisories by severity
    add_index :advisories, [ :severity, :published_at ],
              where: "withdrawn_at IS NULL",
              name: "index_advisories_active_by_severity"

    # ─────────────────────────────────────────────────────────────────────────────
    # PatchBundle indexes
    # ─────────────────────────────────────────────────────────────────────────────
    #
    # Already have: (gem_name, base_branch, state), (state, last_evaluated_at), branch_target_id
    # Adding: standalone state for filtered queries, created_at for time queries

    add_index :patch_bundles, :state, name: "index_patch_bundles_on_state"
    add_index :patch_bundles, :created_at, name: "index_patch_bundles_on_created_at"

    # Partial index for actionable bundles (frequently queried subset)
    add_index :patch_bundles, [ :state, :created_at ],
              where: "state IN ('needs_review', 'ready_for_review')",
              name: "index_patch_bundles_actionable"

    # Partial index for problem bundles
    add_index :patch_bundles, [ :state, :created_at ],
              where: "state IN ('blocked_rate_limited', 'rejected', 'failed')",
              name: "index_patch_bundles_needs_attention"
  end
end
