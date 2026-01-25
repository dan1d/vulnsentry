class BranchTarget < ApplicationRecord
  MAINTENANCE_STATUSES = %w[normal security].freeze

  has_many :candidate_bumps, dependent: :destroy

  validates :name, presence: true, uniqueness: true
  validates :maintenance_status, presence: true, inclusion: { in: MAINTENANCE_STATUSES }
end
