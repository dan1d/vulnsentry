class CreateBotConfigs < ActiveRecord::Migration[8.1]
  def change
    create_table :bot_configs do |t|
      t.boolean :singleton, null: false, default: true
      t.boolean :require_human_approval, null: false, default: true
      t.boolean :emergency_stop, null: false, default: false
      t.boolean :allow_draft_pr, null: false, default: false
      t.integer :global_daily_cap, null: false, default: 3
      t.integer :global_hourly_cap, null: false, default: 1
      t.integer :per_branch_daily_cap, null: false, default: 1
      t.integer :per_gem_daily_cap, null: false, default: 1
      t.integer :rejection_cooldown_hours, null: false, default: 24
      t.string :fork_repo, null: false, default: "dan1d/ruby"
      t.string :upstream_repo, null: false, default: "ruby/ruby"
      t.string :fork_git_url, null: false, default: "git@github.com:dan1d/ruby.git"

      t.timestamps
    end

    add_index :bot_configs, :singleton, unique: true, where: "singleton"
  end
end
