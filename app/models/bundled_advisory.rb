class BundledAdvisory < ApplicationRecord
  belongs_to :patch_bundle
  belongs_to :advisory

  validates :patch_bundle, presence: true
  validates :advisory, presence: true
  validates :advisory_id, uniqueness: { scope: :patch_bundle_id }

  scope :included, -> { where(included_in_fix: true) }
  scope :excluded, -> { where(included_in_fix: false) }

  def cve
    advisory.cve
  end

  def source
    advisory.source
  end
end
