class PullRequest < ApplicationRecord
  belongs_to :candidate_bump

  STATUSES = %w[open closed merged].freeze

  validates :upstream_repo, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
end
