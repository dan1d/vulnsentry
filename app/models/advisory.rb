class Advisory < ApplicationRecord
  SOURCES = %w[ruby_lang ghsa osv].freeze
  SEVERITIES = %w[critical high medium low unknown].freeze

  has_many :candidate_bumps, dependent: :destroy
  has_many :bundled_advisories, dependent: :destroy
  has_many :patch_bundles, through: :bundled_advisories

  validates :gem_name, presence: true
  validates :source, presence: true, inclusion: { in: SOURCES }
  validates :fingerprint, presence: true, uniqueness: true

  # ─────────────────────────────────────────────────────────────────────────────
  # Source-based scopes
  # ─────────────────────────────────────────────────────────────────────────────

  scope :from_ruby_lang, -> { where(source: "ruby_lang") }
  scope :from_ghsa, -> { where(source: "ghsa") }
  scope :from_osv, -> { where(source: "osv") }

  # ─────────────────────────────────────────────────────────────────────────────
  # Gem-related scopes
  # ─────────────────────────────────────────────────────────────────────────────

  # Advisories for bundled gems (gems that ship with Ruby)
  # This is a list of commonly bundled gems - extend as needed
  BUNDLED_GEMS = %w[
    bigdecimal bundler cgi csv date dbm debug delegate did_you_mean
    digest drb english erb etc fcntl fiddle fileutils find forwardable
    getoptlong io-console io-nonblock io-wait ipaddr irb json logger
    matrix minitest mutex_m net-ftp net-http net-imap net-pop net-protocol
    net-smtp nkf observer open-uri open3 openssl optparse ostruct pathname
    pp prettyprint prime pstore psych racc rake rdoc readline reline
    resolv rinda ripper securerandom set shellwords singleton socket
    stringio strscan syslog tempfile time timeout tmpdir tracer tsort
    un unicode_normalize uri weakref win32ole yaml zlib
  ].freeze

  scope :bundled_gems, -> { where(gem_name: BUNDLED_GEMS) }
  scope :for_gem, ->(gem_name) { where(gem_name: gem_name) if gem_name.present? }

  # ─────────────────────────────────────────────────────────────────────────────
  # Severity-based scopes
  # ─────────────────────────────────────────────────────────────────────────────

  scope :by_severity, ->(severity) { where(severity: severity) if severity.present? }
  scope :critical, -> { where(severity: "critical") }
  scope :high, -> { where(severity: "high") }
  scope :medium, -> { where(severity: "medium") }
  scope :low, -> { where(severity: "low") }
  scope :high_or_critical, -> { where(severity: %w[high critical]) }

  # ─────────────────────────────────────────────────────────────────────────────
  # Time-based scopes
  # ─────────────────────────────────────────────────────────────────────────────

  scope :recent, ->(days = 30) { where("published_at >= ?", days.days.ago) }
  scope :published_after, ->(date) { where("published_at >= ?", date) if date.present? }
  scope :published_before, ->(date) { where("published_at <= ?", date) if date.present? }

  # ─────────────────────────────────────────────────────────────────────────────
  # Status scopes
  # ─────────────────────────────────────────────────────────────────────────────

  scope :active, -> { where(withdrawn_at: nil) }
  scope :withdrawn, -> { where.not(withdrawn_at: nil) }
  scope :with_fix, -> { where.not(fixed_version: [ nil, "" ]) }
  scope :without_fix, -> { where(fixed_version: [ nil, "" ]) }
  scope :with_cve, -> { where.not(cve: [ nil, "" ]) }

  # ─────────────────────────────────────────────────────────────────────────────
  # Bundle association scopes
  # ─────────────────────────────────────────────────────────────────────────────

  scope :with_patch_bundles, -> { joins(:patch_bundles).distinct }
  scope :without_patch_bundles, -> {
    where.not(id: BundledAdvisory.select(:advisory_id))
  }

  # ─────────────────────────────────────────────────────────────────────────────
  # Ordering scopes
  # ─────────────────────────────────────────────────────────────────────────────

  scope :by_published, -> { order(published_at: :desc) }
  scope :by_severity_order, -> {
    order(Arel.sql("CASE severity
      WHEN 'critical' THEN 1
      WHEN 'high' THEN 2
      WHEN 'medium' THEN 3
      WHEN 'low' THEN 4
      ELSE 5
    END"))
  }

  # ─────────────────────────────────────────────────────────────────────────────
  # Search scope
  # ─────────────────────────────────────────────────────────────────────────────

  scope :search, ->(query) {
    return all if query.blank?
    q = "%#{sanitize_sql_like(query)}%"
    where("gem_name ILIKE ? OR cve ILIKE ?", q, q)
  }

  # ─────────────────────────────────────────────────────────────────────────────
  # Instance methods
  # ─────────────────────────────────────────────────────────────────────────────

  def active?
    withdrawn_at.nil?
  end

  def withdrawn?
    withdrawn_at.present?
  end

  def has_fix?
    fixed_version.present?
  end

  def severity_level
    SEVERITIES.index(severity&.downcase) || 4
  end

  # OSV returns ISO8601 strings; store them as Time.
  def published_at=(value)
    super(parse_time(value))
  end

  def withdrawn_at=(value)
    super(parse_time(value))
  end

  private
    def parse_time(value)
      return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
      return nil if value.blank?
      Time.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end
end
