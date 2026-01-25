class CreatePullRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :pull_requests do |t|
      t.references :candidate_bump, null: false, foreign_key: true, index: { unique: true }
      t.string :upstream_repo, null: false, default: "ruby/ruby"
      t.integer :pr_number
      t.text :pr_url
      t.string :status, null: false, default: "open"
      t.datetime :opened_at
      t.datetime :merged_at
      t.datetime :closed_at
      t.datetime :last_synced_at

      t.timestamps
    end

    add_index :pull_requests, [ :upstream_repo, :pr_number ], unique: true, where: "pr_number IS NOT NULL"
  end
end
