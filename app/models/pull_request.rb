class PullRequest < ApplicationRecord
  belongs_to :candidate_bump

  STATUSES = %w[open closed merged].freeze
  REVIEW_STATES = %w[pending approved changes_requested].freeze

  validates :upstream_repo, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :review_state, inclusion: { in: REVIEW_STATES }, allow_nil: true
end
