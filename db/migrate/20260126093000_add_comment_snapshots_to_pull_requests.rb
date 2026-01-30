class AddCommentSnapshotsToPullRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :pull_requests, :comments_snapshot, :jsonb, null: false, default: {}
    add_column :pull_requests, :comments_last_synced_at, :datetime
  end
end
