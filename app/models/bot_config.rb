class BotConfig < ApplicationRecord
  validate :enforce_singleton

  def self.instance
    find_by(singleton: true) || create!
  end

  private
    def enforce_singleton
      return unless singleton?
      return if self.class.where(singleton: true).where.not(id: id).none?

      errors.add(:singleton, "must be unique")
    end
end
