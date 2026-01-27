class MakeCandidateBumpNullableOnPullRequests < ActiveRecord::Migration[8.1]
  def change
    change_column_null :pull_requests, :candidate_bump_id, true
  end
end
