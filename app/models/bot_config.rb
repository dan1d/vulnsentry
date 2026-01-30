class BotConfig < ApplicationRecord
  validate :enforce_singleton

  def self.instance
    find_by(singleton: true) || create!
  end

  # Returns the default/primary project (Ruby Core)
  # Used for backwards compatibility during migration
  def default_project
    Project.find_by(slug: "ruby") || Project.enabled.first
  end

  # Delegate to default project for backwards compatibility
  # These will be removed once all code uses Project directly
  def upstream_repo
    default_project&.upstream_repo || "ruby/ruby"
  end

  def fork_repo
    default_project&.fork_repo || "dan1d/ruby"
  end

  def fork_git_url
    default_project&.fork_git_url || "git@github.com:dan1d/ruby.git"
  end

  private
    def enforce_singleton
      return unless singleton?
      return if self.class.where(singleton: true).where.not(id: id).none?

      errors.add(:singleton, "must be unique")
    end
end
