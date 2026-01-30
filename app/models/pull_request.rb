class PullRequest < ApplicationRecord
  belongs_to :project, optional: true
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

  scope :for_project, ->(project) { where(project: project) }

  # Set project from patch_bundle if not explicitly set
  before_validation :infer_project_from_bundle

  private

  def has_parent_reference
    # Important: in tests and in-memory objects, associations may be present
    # even when the foreign key isn't persisted yet.
    return if candidate_bump.present? || patch_bundle.present?

    errors.add(:base, "must belong to either candidate_bump or patch_bundle")
  end

  def infer_project_from_bundle
    self.project ||= patch_bundle&.branch_target&.project
  end
end
