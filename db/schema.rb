# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_01_30_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "admin_users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.string "username", null: false
    t.index ["username"], name: "index_admin_users_on_username", unique: true
  end

  create_table "advisories", force: :cascade do |t|
    t.text "advisory_url"
    t.text "affected_requirement"
    t.datetime "created_at", null: false
    t.string "cve"
    t.string "fingerprint", null: false
    t.string "fixed_version"
    t.string "gem_name", null: false
    t.datetime "published_at"
    t.jsonb "raw", default: {}, null: false
    t.string "severity"
    t.string "source", null: false
    t.datetime "updated_at", null: false
    t.datetime "withdrawn_at"
    t.index ["fingerprint"], name: "index_advisories_on_fingerprint", unique: true
    t.index ["gem_name"], name: "index_advisories_on_gem_name"
    t.index ["published_at"], name: "index_advisories_on_published_at"
    t.index ["severity", "published_at"], name: "index_advisories_active_by_severity", where: "(withdrawn_at IS NULL)"
    t.index ["severity"], name: "index_advisories_on_severity"
    t.index ["source"], name: "index_advisories_on_source"
  end

  create_table "bot_configs", force: :cascade do |t|
    t.boolean "allow_draft_pr", default: false, null: false
    t.datetime "created_at", null: false
    t.boolean "emergency_stop", default: false, null: false
    t.string "fork_git_url", default: "git@github.com:dan1d/ruby.git", null: false
    t.string "fork_repo", default: "dan1d/ruby", null: false
    t.integer "global_daily_cap", default: 3, null: false
    t.integer "global_hourly_cap", default: 1, null: false
    t.integer "per_branch_daily_cap", default: 1, null: false
    t.integer "per_gem_daily_cap", default: 1, null: false
    t.integer "rejection_cooldown_hours", default: 24, null: false
    t.boolean "require_human_approval", default: true, null: false
    t.boolean "singleton", default: true, null: false
    t.datetime "updated_at", null: false
    t.string "upstream_repo", default: "ruby/ruby", null: false
    t.index ["singleton"], name: "index_bot_configs_on_singleton", unique: true, where: "singleton"
  end

  create_table "branch_targets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "last_checked_at"
    t.datetime "last_seen_at"
    t.string "maintenance_status", null: false
    t.string "name", null: false
    t.text "source_url"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_branch_targets_on_name", unique: true
  end

  create_table "bundled_advisories", force: :cascade do |t|
    t.bigint "advisory_id", null: false
    t.datetime "created_at", null: false
    t.text "exclusion_reason"
    t.boolean "included_in_fix", default: true, null: false
    t.bigint "patch_bundle_id", null: false
    t.string "suggested_fix_version"
    t.datetime "updated_at", null: false
    t.index ["advisory_id", "patch_bundle_id"], name: "index_bundled_advisories_on_advisory_id_and_patch_bundle_id", unique: true
    t.index ["advisory_id"], name: "index_bundled_advisories_on_advisory_id"
    t.index ["patch_bundle_id"], name: "index_bundled_advisories_on_patch_bundle_id"
  end

  create_table "candidate_bumps", force: :cascade do |t|
    t.bigint "advisory_id", null: false
    t.datetime "approved_at"
    t.string "approved_by"
    t.string "base_branch", null: false
    t.text "blocked_reason"
    t.bigint "branch_target_id", null: false
    t.datetime "created_at", null: false
    t.datetime "created_pr_at"
    t.string "current_version", null: false
    t.string "gem_name", null: false
    t.datetime "last_attempted_at"
    t.datetime "next_eligible_at"
    t.text "proposed_diff"
    t.text "review_notes"
    t.string "state", default: "pending", null: false
    t.string "target_version", null: false
    t.datetime "updated_at", null: false
    t.index ["advisory_id", "base_branch", "target_version"], name: "index_candidate_bumps_dedupe", unique: true
    t.index ["advisory_id"], name: "index_candidate_bumps_on_advisory_id"
    t.index ["branch_target_id"], name: "index_candidate_bumps_on_branch_target_id"
    t.index ["gem_name", "base_branch", "state"], name: "index_candidate_bumps_on_gem_name_and_base_branch_and_state"
  end

  create_table "patch_bundles", force: :cascade do |t|
    t.datetime "approved_at"
    t.string "approved_by"
    t.string "base_branch", null: false
    t.text "blocked_reason"
    t.bigint "branch_target_id", null: false
    t.datetime "created_at", null: false
    t.datetime "created_pr_at"
    t.string "current_version", null: false
    t.string "gem_name", null: false
    t.datetime "last_attempted_at"
    t.datetime "last_evaluated_at"
    t.jsonb "llm_recommendation", default: {}
    t.datetime "next_eligible_at"
    t.text "proposed_diff"
    t.string "resolution_source"
    t.text "review_notes"
    t.string "state", default: "pending", null: false
    t.string "target_version"
    t.datetime "updated_at", null: false
    t.index ["branch_target_id", "gem_name", "current_version"], name: "index_patch_bundles_unique_per_branch_gem", unique: true
    t.index ["branch_target_id"], name: "index_patch_bundles_on_branch_target_id"
    t.index ["created_at"], name: "index_patch_bundles_on_created_at"
    t.index ["gem_name", "base_branch", "state"], name: "index_patch_bundles_on_gem_name_and_base_branch_and_state"
    t.index ["state", "created_at"], name: "index_patch_bundles_actionable", where: "((state)::text = ANY (ARRAY[('needs_review'::character varying)::text, ('ready_for_review'::character varying)::text]))"
    t.index ["state", "created_at"], name: "index_patch_bundles_needs_attention", where: "((state)::text = ANY (ARRAY[('blocked_rate_limited'::character varying)::text, ('rejected'::character varying)::text, ('failed'::character varying)::text]))"
    t.index ["state", "last_evaluated_at"], name: "index_patch_bundles_for_reevaluation"
    t.index ["state"], name: "index_patch_bundles_on_state"
  end

  create_table "pull_requests", force: :cascade do |t|
    t.text "body"
    t.datetime "branch_deleted_at"
    t.bigint "candidate_bump_id"
    t.datetime "closed_at"
    t.datetime "comments_last_synced_at"
    t.jsonb "comments_snapshot", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "fork_repo", default: "dan1d/ruby", null: false
    t.string "head_branch"
    t.jsonb "labels", default: [], null: false
    t.datetime "last_synced_at"
    t.datetime "merged_at"
    t.datetime "opened_at"
    t.bigint "patch_bundle_id"
    t.integer "pr_number"
    t.text "pr_url"
    t.string "review_state"
    t.string "status", default: "open", null: false
    t.datetime "updated_at", null: false
    t.string "upstream_repo", default: "ruby/ruby", null: false
    t.index ["branch_deleted_at"], name: "index_pull_requests_on_branch_deleted_at"
    t.index ["candidate_bump_id"], name: "index_pull_requests_on_candidate_bump_id", unique: true
    t.index ["fork_repo", "head_branch"], name: "index_pull_requests_on_fork_repo_and_head_branch"
    t.index ["patch_bundle_id"], name: "index_pull_requests_on_patch_bundle_id"
    t.index ["patch_bundle_id"], name: "index_pull_requests_on_patch_bundle_unique", unique: true, where: "(patch_bundle_id IS NOT NULL)"
    t.index ["upstream_repo", "pr_number"], name: "index_pull_requests_on_upstream_repo_and_pr_number", unique: true, where: "(pr_number IS NOT NULL)"
  end

  create_table "system_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.text "message"
    t.datetime "occurred_at", null: false
    t.jsonb "payload", default: {}, null: false
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["kind", "occurred_at"], name: "index_system_events_on_kind_and_occurred_at"
    t.index ["occurred_at"], name: "index_system_events_on_occurred_at"
    t.index ["payload"], name: "index_system_events_on_payload_gin", using: :gin
    t.index ["status", "occurred_at"], name: "index_system_events_on_status_and_occurred_at"
  end

  add_foreign_key "bundled_advisories", "advisories"
  add_foreign_key "bundled_advisories", "patch_bundles"
  add_foreign_key "candidate_bumps", "advisories"
  add_foreign_key "candidate_bumps", "branch_targets"
  add_foreign_key "patch_bundles", "branch_targets"
  add_foreign_key "pull_requests", "candidate_bumps"
  add_foreign_key "pull_requests", "patch_bundles"
end
