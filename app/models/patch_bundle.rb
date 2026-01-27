class PatchBundle < ApplicationRecord
  belongs_to :branch_target

  has_many :bundled_advisories, dependent: :destroy
  has_many :advisories, through: :bundled_advisories
  has_one :pull_request, dependent: :destroy

  STATES = %w[
    pending
    awaiting_fix
    needs_review
    ready_for_review
    blocked_rate_limited
    approved
    rejected
    submitted
    failed
  ].freeze

  RESOLUTION_SOURCES = %w[auto llm manual].freeze

  validates :base_branch, presence: true
  validates :gem_name, presence: true
  validates :current_version, presence: true
  validates :state, presence: true, inclusion: { in: STATES }
  validates :resolution_source, inclusion: { in: RESOLUTION_SOURCES }, allow_nil: true

  scope :awaiting_fix, -> { where(state: "awaiting_fix") }
  scope :needs_reevaluation, ->(hours_ago = 24) {
    awaiting_fix.where("last_evaluated_at IS NULL OR last_evaluated_at < ?", hours_ago.hours.ago)
  }
  scope :ready_for_review, -> { where(state: "ready_for_review") }
  scope :approved, -> { where(state: "approved") }

  def has_fix?
    target_version.present? && target_version != current_version
  end

  def bump_display
    if has_fix?
      "#{current_version} → #{target_version}"
    else
      "#{current_version} → ?"
    end
  end

  def advisory_count
    bundled_advisories.count
  end

  def cve_list
    advisories.pluck(:cve).compact
  end
end
