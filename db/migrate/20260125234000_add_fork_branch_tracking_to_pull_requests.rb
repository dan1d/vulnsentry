class AddForkBranchTrackingToPullRequests < ActiveRecord::Migration[8.1]
  def change
    change_table :pull_requests, bulk: true do |t|
      t.string :fork_repo, null: false, default: "dan1d/ruby"
      t.string :head_branch
      t.datetime :branch_deleted_at
    end

    add_index :pull_requests, [ :fork_repo, :head_branch ]
    add_index :pull_requests, :branch_deleted_at
  end
end
