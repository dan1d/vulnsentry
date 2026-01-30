# frozen_string_literal: true

class CreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.string :name, null: false                    # "Ruby Core", "Rails"
      t.string :slug, null: false                    # "ruby", "rails" (URL-friendly)
      t.string :upstream_repo, null: false           # "ruby/ruby", "rails/rails"
      t.string :fork_repo                            # "vulnsentry-bot/ruby"
      t.string :fork_git_url                         # "git@github.com:vulnsentry-bot/ruby.git"
      t.string :file_type, null: false               # "bundled_gems", "gemfile_lock"
      t.string :file_path, null: false               # "gems/bundled_gems", "Gemfile.lock"
      t.string :branch_discovery, default: "manual"  # "ruby_lang", "github_releases", "manual"
      t.boolean :enabled, default: true, null: false
      t.jsonb :settings, default: {}, null: false   # Per-project rate limits, etc.
      t.timestamps

      t.index :slug, unique: true
      t.index :upstream_repo, unique: true
      t.index :enabled
    end
  end
end
