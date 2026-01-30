# frozen_string_literal: true

# Constants for SystemEvent kinds used throughout the application.
# Include in SystemEvent model to access as SystemEvent::KINDS::*
module SystemEventKinds
  extend ActiveSupport::Concern

  # Advisory and security-related events
  ADVISORY_INGEST = "advisory_ingest"
  GHSA_INGEST = "ghsa_ingest"
  OSV_INGEST = "osv_ingest"
  RUBY_LANG_RESOLVER = "ruby_lang_resolver"

  # Branch and repository events
  BRANCH_REFRESH = "branch_refresh"
  FORK_BRANCH_CLEANUP = "fork_branch_cleanup"

  # Evaluation and bundle building events
  BUNDLED_GEMS_FETCH = "bundled_gems_fetch"
  PATCH_BUNDLE_BUILD = "patch_bundle_build"
  PATCH_BUNDLE_REEVALUATION = "patch_bundle_reevaluation"
  REEVALUATE_AWAITING_FIX = "reevaluate_awaiting_fix"
  CANDIDATE_BUILD = "candidate_build"
  EVALUATION = "evaluation"

  # Pull request events
  CREATE_PR = "create_pr"
  CREATE_PATCH_BUNDLE_PR = "create_patch_bundle_pr"
  PR_CREATION = "pr_creation"
  SYNC_PULL_REQUESTS = "sync_pull_requests"
  MAINTAINER_FEEDBACK = "maintainer_feedback"

  # System events
  SEED = "seed"

  # All known event kinds (for validation, filtering, etc.)
  ALL_KINDS = [
    ADVISORY_INGEST,
    GHSA_INGEST,
    OSV_INGEST,
    RUBY_LANG_RESOLVER,
    BRANCH_REFRESH,
    FORK_BRANCH_CLEANUP,
    BUNDLED_GEMS_FETCH,
    PATCH_BUNDLE_BUILD,
    PATCH_BUNDLE_REEVALUATION,
    REEVALUATE_AWAITING_FIX,
    CANDIDATE_BUILD,
    EVALUATION,
    CREATE_PR,
    CREATE_PATCH_BUNDLE_PR,
    PR_CREATION,
    SYNC_PULL_REQUESTS,
    MAINTAINER_FEEDBACK,
    SEED
  ].freeze

  # Grouped by category for UI display
  ADVISORY_KINDS = [
    ADVISORY_INGEST,
    GHSA_INGEST,
    OSV_INGEST,
    RUBY_LANG_RESOLVER
  ].freeze

  BRANCH_KINDS = [
    BRANCH_REFRESH,
    FORK_BRANCH_CLEANUP
  ].freeze

  EVALUATION_KINDS = [
    BUNDLED_GEMS_FETCH,
    PATCH_BUNDLE_BUILD,
    PATCH_BUNDLE_REEVALUATION,
    REEVALUATE_AWAITING_FIX,
    CANDIDATE_BUILD,
    EVALUATION
  ].freeze

  PR_KINDS = [
    CREATE_PR,
    CREATE_PATCH_BUNDLE_PR,
    PR_CREATION,
    SYNC_PULL_REQUESTS,
    MAINTAINER_FEEDBACK
  ].freeze

  included do
    # Class methods for options_for_select dropdowns
    def self.kind_options_for_select
      SystemEventKinds::ALL_KINDS.map { |k| [ k.titleize, k ] }
    end

    def self.grouped_kind_options_for_select
      {
        "Advisory" => SystemEventKinds::ADVISORY_KINDS.map { |k| [ k.titleize, k ] },
        "Branch" => SystemEventKinds::BRANCH_KINDS.map { |k| [ k.titleize, k ] },
        "Evaluation" => SystemEventKinds::EVALUATION_KINDS.map { |k| [ k.titleize, k ] },
        "Pull Request" => SystemEventKinds::PR_KINDS.map { |k| [ k.titleize, k ] }
      }
    end
  end
end
