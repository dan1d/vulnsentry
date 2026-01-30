class SystemEvent < ApplicationRecord
  include SystemEventKinds

  STATUSES = %w[ok warning failed].freeze

  validates :kind, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :occurred_at, presence: true

  # ─────────────────────────────────────────────────────────────────────────────
  # Scopes for filtering
  # ─────────────────────────────────────────────────────────────────────────────

  # Filter by event kind
  scope :by_kind, ->(kind) { where(kind: kind) if kind.present? }

  # Filter by status
  scope :by_status, ->(status) { where(status: status) if status.present? }

  # Filter by date range
  scope :by_date_range, ->(start_date, end_date = nil) {
    rel = all
    rel = rel.where("occurred_at >= ?", start_date) if start_date.present?
    rel = rel.where("occurred_at <= ?", end_date) if end_date.present?
    rel
  }

  # Filter events that occurred after a given time
  scope :occurred_after, ->(time) { where("occurred_at >= ?", time) if time.present? }

  # Filter events that occurred before a given time
  scope :occurred_before, ->(time) { where("occurred_at <= ?", time) if time.present? }

  # Search in message and payload (case-insensitive)
  scope :search, ->(query) {
    return all if query.blank?
    q = "%#{sanitize_sql_like(query)}%"
    where("message ILIKE ? OR CAST(payload AS text) ILIKE ?", q, q)
  }

  # Filter by gem_name in payload
  scope :for_gem, ->(gem_name) {
    where("(payload ->> 'gem_name') = ?", gem_name) if gem_name.present?
  }

  # Filter by branch in payload
  scope :for_branch, ->(branch) {
    where("(payload ->> 'branch') = ?", branch) if branch.present?
  }

  # ─────────────────────────────────────────────────────────────────────────────
  # Status-based scopes
  # ─────────────────────────────────────────────────────────────────────────────

  scope :ok, -> { where(status: "ok") }
  scope :warnings, -> { where(status: "warning") }
  scope :failed, -> { where(status: "failed") }

  # ─────────────────────────────────────────────────────────────────────────────
  # Time-based scopes
  # ─────────────────────────────────────────────────────────────────────────────

  scope :recent, ->(limit = 50) { order(occurred_at: :desc).limit(limit) }
  scope :today, -> { where("occurred_at >= ?", Time.current.beginning_of_day) }
  scope :last_24_hours, -> { where("occurred_at >= ?", 24.hours.ago) }
  scope :last_7_days, -> { where("occurred_at >= ?", 7.days.ago) }

  # ─────────────────────────────────────────────────────────────────────────────
  # Category-based scopes (using grouped kinds)
  # ─────────────────────────────────────────────────────────────────────────────

  scope :advisory_events, -> { where(kind: ADVISORY_KINDS) }
  scope :branch_events, -> { where(kind: BRANCH_KINDS) }
  scope :evaluation_events, -> { where(kind: EVALUATION_KINDS) }
  scope :pr_events, -> { where(kind: PR_KINDS) }

  # ─────────────────────────────────────────────────────────────────────────────
  # Ordering scopes
  # ─────────────────────────────────────────────────────────────────────────────

  scope :chronological, -> { order(occurred_at: :asc) }
  scope :reverse_chronological, -> { order(occurred_at: :desc) }

  # ─────────────────────────────────────────────────────────────────────────────
  # Instance methods
  # ─────────────────────────────────────────────────────────────────────────────

  def ok?
    status == "ok"
  end

  def warning?
    status == "warning"
  end

  def failed?
    status == "failed"
  end

  def gem_name
    payload["gem_name"]
  end

  def branch
    payload["branch"]
  end
end
