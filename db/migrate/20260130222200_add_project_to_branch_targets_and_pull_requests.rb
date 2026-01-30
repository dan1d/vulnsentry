# frozen_string_literal: true

class AddProjectToBranchTargetsAndPullRequests < ActiveRecord::Migration[8.1]
  def up
    # Add nullable project_id columns first
    add_reference :branch_targets, :project, null: true, foreign_key: true, index: true
    add_reference :pull_requests, :project, null: true, foreign_key: true, index: true

    # Create default Ruby project if it doesn't exist
    # Uses raw SQL to avoid model dependencies during migration
    execute <<~SQL
      INSERT INTO projects (name, slug, upstream_repo, fork_repo, fork_git_url, file_type, file_path, branch_discovery, enabled, settings, created_at, updated_at)
      SELECT 'Ruby Core', 'ruby', 'ruby/ruby', 'dan1d/ruby', 'git@github.com:dan1d/ruby.git', 'bundled_gems', 'gems/bundled_gems', 'ruby_lang', true, '{}', NOW(), NOW()
      WHERE NOT EXISTS (SELECT 1 FROM projects WHERE slug = 'ruby')
    SQL

    # Backfill existing records to the Ruby project
    execute <<~SQL
      UPDATE branch_targets#{' '}
      SET project_id = (SELECT id FROM projects WHERE slug = 'ruby')
      WHERE project_id IS NULL
    SQL

    execute <<~SQL
      UPDATE pull_requests#{' '}
      SET project_id = (SELECT id FROM projects WHERE slug = 'ruby')
      WHERE project_id IS NULL
    SQL

    # Make project_id non-nullable on branch_targets (required association)
    change_column_null :branch_targets, :project_id, false

    # Update unique index on branch_targets to include project
    remove_index :branch_targets, :name
    add_index :branch_targets, [ :project_id, :name ], unique: true
  end

  def down
    # Restore original index
    remove_index :branch_targets, [ :project_id, :name ]
    add_index :branch_targets, :name, unique: true

    # Remove foreign keys and columns
    remove_reference :pull_requests, :project
    remove_reference :branch_targets, :project
  end
end
