class PullRequest < ApplicationRecord
  # Legacy: belongs_to candidate_bump (will be deprecated)
  belongs_to :candidate_bump, optional: true
  # New: belongs_to patch_bundle
  belongs_to :patch_bundle, optional: true

  STATUSES = %w[open closed merged].freeze
  REVIEW_STATES = %w[pending approved changes_requested].freeze

  validates :upstream_repo, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :review_state, inclusion: { in: REVIEW_STATES }, allow_nil: true
  validate :has_parent_reference

  private

  def has_parent_reference
    return if candidate_bump_id.present? || patch_bundle_id.present?

    errors.add(:base, "must belong to either candidate_bump or patch_bundle")
  end
end
