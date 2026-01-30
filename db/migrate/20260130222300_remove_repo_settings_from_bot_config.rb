# frozen_string_literal: true

class RemoveRepoSettingsFromBotConfig < ActiveRecord::Migration[8.1]
  def up
    # Remove repo-specific columns that are now on Project
    remove_column :bot_configs, :upstream_repo
    remove_column :bot_configs, :fork_repo
    remove_column :bot_configs, :fork_git_url
  end

  def down
    # Re-add columns with their original defaults
    add_column :bot_configs, :upstream_repo, :string, default: "ruby/ruby", null: false
    add_column :bot_configs, :fork_repo, :string, default: "dan1d/ruby", null: false
    add_column :bot_configs, :fork_git_url, :string, default: "git@github.com:dan1d/ruby.git", null: false
  end
end
