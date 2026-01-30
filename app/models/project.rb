# frozen_string_literal: true

# Represents a monitored open-source project (e.g., ruby/ruby, rails/rails).
# Each project has its own branch targets, dependency file format, and fork configuration.
class Project < ApplicationRecord
  # File types supported for dependency tracking
  FILE_TYPES = %w[bundled_gems gemfile_lock].freeze

  # Branch discovery methods
  BRANCH_DISCOVERY_METHODS = %w[ruby_lang github_releases manual].freeze

  has_many :branch_targets, dependent: :destroy
  has_many :patch_bundles, through: :branch_targets
  has_many :pull_requests, dependent: :nullify

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_-]+\z/, message: "must be lowercase alphanumeric with dashes/underscores" }
  validates :upstream_repo, presence: true, uniqueness: true, format: { with: %r{\A[^/]+/[^/]+\z}, message: "must be in owner/repo format" }
  validates :file_type, presence: true, inclusion: { in: FILE_TYPES }
  validates :file_path, presence: true
  validates :branch_discovery, inclusion: { in: BRANCH_DISCOVERY_METHODS }

  scope :enabled, -> { where(enabled: true) }

  # Returns the appropriate file parser class for this project's file type
  def file_parser_class
    case file_type
    when "bundled_gems"
      require_dependency "project_files/bundled_gems_file"
      ProjectFiles::BundledGemsFile
    when "gemfile_lock"
      require_dependency "project_files/gemfile_lock_file"
      ProjectFiles::GemfileLockFile
    else
      raise ArgumentError, "Unknown file type: #{file_type}"
    end
  end

  # Returns a configured file fetcher for this project
  def file_fetcher
    ProjectFiles::Fetcher.new(self)
  end

  # Parse the dependency file content using the appropriate parser
  def parse_file(content)
    file_parser_class.new(content)
  end

  # GitHub HTTPS URL for cloning
  def upstream_https_url
    "https://github.com/#{upstream_repo}.git"
  end

  # Check if this project has fork configuration for PR creation
  def can_create_prs?
    fork_repo.present? && fork_git_url.present?
  end

  # Human-readable display name
  def display_name
    name.presence || slug.titleize
  end

  # Short identifier for logs and events
  def to_param
    slug
  end
end
