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

  # States that require user attention
  ACTIONABLE_STATES = %w[needs_review ready_for_review].freeze

  # States that indicate a problem
  PROBLEM_STATES = %w[blocked_rate_limited rejected failed].freeze

  # Terminal states (no further action expected)
  TERMINAL_STATES = %w[submitted rejected failed].freeze

  # Active states (work in progress)
  ACTIVE_STATES = %w[pending awaiting_fix needs_review ready_for_review approved].freeze

  RESOLUTION_SOURCES = %w[auto llm manual].freeze

  validates :base_branch, presence: true
  validates :gem_name, presence: true
  validates :current_version, presence: true
  validates :state, presence: true, inclusion: { in: STATES }
  validates :resolution_source, inclusion: { in: RESOLUTION_SOURCES }, allow_nil: true

  # ─────────────────────────────────────────────────────────────────────────────
  # State-based scopes
  # ─────────────────────────────────────────────────────────────────────────────

  scope :by_state, ->(state) { where(state: state) if state.present? }
  scope :pending, -> { where(state: "pending") }
  scope :awaiting_fix, -> { where(state: "awaiting_fix") }
  scope :needs_review, -> { where(state: "needs_review") }
  scope :ready_for_review, -> { where(state: "ready_for_review") }
  scope :blocked_rate_limited, -> { where(state: "blocked_rate_limited") }
  scope :approved, -> { where(state: "approved") }
  scope :rejected, -> { where(state: "rejected") }
  scope :submitted, -> { where(state: "submitted") }
  scope :failed, -> { where(state: "failed") }

  # ─────────────────────────────────────────────────────────────────────────────
  # Aggregated state scopes
  # ─────────────────────────────────────────────────────────────────────────────

  # Bundles that require human attention
  scope :actionable, -> { where(state: ACTIONABLE_STATES) }

  # Bundles with problems that need attention
  scope :needs_attention, -> { where(state: PROBLEM_STATES) }

  # Bundles that are still being processed
  scope :active, -> { where(state: ACTIVE_STATES) }

  # Bundles that are complete (success or failure)
  scope :terminal, -> { where(state: TERMINAL_STATES) }

  # ─────────────────────────────────────────────────────────────────────────────
  # Reevaluation scopes
  # ─────────────────────────────────────────────────────────────────────────────

  scope :needs_reevaluation, ->(hours_ago = 24) {
    awaiting_fix.where("last_evaluated_at IS NULL OR last_evaluated_at < ?", hours_ago.hours.ago)
  }

  scope :stale, ->(hours_ago = 48) {
    where("last_evaluated_at IS NULL OR last_evaluated_at < ?", hours_ago.hours.ago)
  }

  scope :never_evaluated, -> { where(last_evaluated_at: nil) }

  # ─────────────────────────────────────────────────────────────────────────────
  # Fix status scopes
  # ─────────────────────────────────────────────────────────────────────────────

  scope :with_fix, -> { where.not(target_version: [ nil, "" ]) }
  scope :without_fix, -> { where(target_version: [ nil, "" ]) }

  # ─────────────────────────────────────────────────────────────────────────────
  # Branch and gem scopes
  # ─────────────────────────────────────────────────────────────────────────────

  scope :for_branch, ->(branch) { where(base_branch: branch) if branch.present? }
  scope :for_gem, ->(gem_name) { where(gem_name: gem_name) if gem_name.present? }

  # ─────────────────────────────────────────────────────────────────────────────
  # Resolution source scopes
  # ─────────────────────────────────────────────────────────────────────────────

  scope :resolved_by_auto, -> { where(resolution_source: "auto") }
  scope :resolved_by_llm, -> { where(resolution_source: "llm") }
  scope :resolved_by_manual, -> { where(resolution_source: "manual") }
  scope :unresolved, -> { where(resolution_source: nil) }

  # ─────────────────────────────────────────────────────────────────────────────
  # Time-based scopes
  # ─────────────────────────────────────────────────────────────────────────────

  scope :recent, ->(days = 7) { where("created_at >= ?", days.days.ago) }
  scope :created_after, ->(date) { where("created_at >= ?", date) if date.present? }
  scope :approved_today, -> { approved.where("approved_at >= ?", Time.current.beginning_of_day) }

  # ─────────────────────────────────────────────────────────────────────────────
  # Ordering scopes
  # ─────────────────────────────────────────────────────────────────────────────

  scope :by_priority, -> {
    order(Arel.sql("CASE state
      WHEN 'ready_for_review' THEN 1
      WHEN 'needs_review' THEN 2
      WHEN 'awaiting_fix' THEN 3
      WHEN 'pending' THEN 4
      WHEN 'approved' THEN 5
      WHEN 'blocked_rate_limited' THEN 6
      WHEN 'failed' THEN 7
      WHEN 'rejected' THEN 8
      WHEN 'submitted' THEN 9
      ELSE 10
    END"))
  }

  scope :by_recent, -> { order(created_at: :desc) }
  scope :by_oldest, -> { order(created_at: :asc) }

  # ─────────────────────────────────────────────────────────────────────────────
  # Search scope
  # ─────────────────────────────────────────────────────────────────────────────

  scope :search, ->(query) {
    return all if query.blank?
    q = "%#{sanitize_sql_like(query)}%"
    where("gem_name ILIKE ? OR base_branch ILIKE ?", q, q)
  }

  # ─────────────────────────────────────────────────────────────────────────────
  # PR-related scopes
  # ─────────────────────────────────────────────────────────────────────────────

  scope :with_pr, -> { joins(:pull_request) }
  scope :without_pr, -> { left_joins(:pull_request).where(pull_requests: { id: nil }) }

  # ─────────────────────────────────────────────────────────────────────────────
  # Instance methods
  # ─────────────────────────────────────────────────────────────────────────────

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

  def actionable?
    ACTIONABLE_STATES.include?(state)
  end

  def needs_attention?
    PROBLEM_STATES.include?(state)
  end

  def terminal?
    TERMINAL_STATES.include?(state)
  end

  def active?
    ACTIVE_STATES.include?(state)
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # LLM recommendation helpers
  # ─────────────────────────────────────────────────────────────────────────────

  def llm_confidence
    llm_recommendation&.dig("confidence")
  end

  def llm_rationale
    llm_recommendation&.dig("rationale")
  end

  def llm_recommended_version
    llm_recommendation&.dig("recommended_version")
  end

  def llm_resolved?
    resolution_source == "llm"
  end

  # LLM resolution scopes
  scope :llm_resolved, -> { where(resolution_source: "llm") }
  scope :with_high_confidence, -> { llm_resolved.where("llm_recommendation->>'confidence' = ?", "high") }
  scope :with_medium_confidence, -> { llm_resolved.where("llm_recommendation->>'confidence' = ?", "medium") }
  scope :with_low_confidence, -> { llm_resolved.where("llm_recommendation->>'confidence' = ?", "low") }
end
