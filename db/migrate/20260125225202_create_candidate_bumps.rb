class CreateCandidateBumps < ActiveRecord::Migration[8.1]
  def change
    create_table :candidate_bumps do |t|
      t.references :advisory, null: false, foreign_key: true
      t.references :branch_target, null: false, foreign_key: true
      t.string :base_branch, null: false
      t.string :gem_name, null: false
      t.string :current_version, null: false
      t.string :target_version, null: false
      t.string :state, null: false, default: "pending"
      t.text :blocked_reason
      t.text :proposed_diff
      t.text :review_notes
      t.datetime :approved_at
      t.string :approved_by
      t.datetime :created_pr_at
      t.datetime :last_attempted_at
      t.datetime :next_eligible_at

      t.timestamps
    end

    add_index :candidate_bumps, [ :advisory_id, :base_branch, :target_version ], unique: true, name: "index_candidate_bumps_dedupe"
    add_index :candidate_bumps, [ :gem_name, :base_branch, :state ]
  end
end
