class Advisory < ApplicationRecord
  SOURCES = %w[ruby_lang ghsa osv].freeze

  has_many :candidate_bumps, dependent: :destroy

  validates :gem_name, presence: true
  validates :source, presence: true, inclusion: { in: SOURCES }
  validates :fingerprint, presence: true, uniqueness: true

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
