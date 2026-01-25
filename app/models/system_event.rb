class SystemEvent < ApplicationRecord
  STATUSES = %w[ok warning failed].freeze

  validates :kind, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :occurred_at, presence: true
end
