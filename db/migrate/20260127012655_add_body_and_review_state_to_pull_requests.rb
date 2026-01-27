class AddBodyAndReviewStateToPullRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :pull_requests, :body, :text
    add_column :pull_requests, :review_state, :string
    add_column :pull_requests, :labels, :jsonb, default: [], null: false
  end
end
