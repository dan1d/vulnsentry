class Advisory < ApplicationRecord
  SOURCES = %w[ruby_lang ghsa osv].freeze

  has_many :candidate_bumps, dependent: :destroy

  validates :gem_name, presence: true
  validates :source, presence: true, inclusion: { in: SOURCES }
  validates :fingerprint, presence: true, uniqueness: true
end
