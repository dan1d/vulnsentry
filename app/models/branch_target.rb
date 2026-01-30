class BranchTarget < ApplicationRecord
  MAINTENANCE_STATUSES = %w[normal security eol].freeze

  belongs_to :project
  has_many :candidate_bumps, dependent: :destroy
  has_many :patch_bundles, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :project_id, message: "must be unique within project" }
  validates :maintenance_status, presence: true, inclusion: { in: MAINTENANCE_STATUSES }

  scope :enabled, -> { where(enabled: true) }
  scope :active, -> { enabled.where.not(maintenance_status: "eol") }

  # Delegate project attributes for convenience
  delegate :upstream_repo, :fork_repo, :fork_git_url, :file_type, :file_path, to: :project

  def eol?
    maintenance_status == "eol"
  end

  def security_only?
    maintenance_status == "security"
  end

  def normal?
    maintenance_status == "normal"
  end
end
