class CandidateBump < ApplicationRecord
  belongs_to :advisory
  belongs_to :branch_target

  STATES = %w[
    pending
    blocked_rate_limited
    blocked_ambiguous
    ready_for_review
    approved
    rejected
    submitted
    failed
  ].freeze

  has_one :pull_request, dependent: :destroy

  validates :base_branch, presence: true
  validates :gem_name, presence: true
  validates :current_version, presence: true
  validates :target_version, presence: true
  validates :state, presence: true, inclusion: { in: STATES }
end
