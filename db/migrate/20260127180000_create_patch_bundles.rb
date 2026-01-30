class CreatePatchBundles < ActiveRecord::Migration[8.1]
  def change
    create_table :patch_bundles do |t|
      t.references :branch_target, null: false, foreign_key: true
      t.string :base_branch, null: false
      t.string :gem_name, null: false
      t.string :current_version, null: false
      t.string :target_version          # nullable: nil when awaiting_fix
      t.string :state, null: false, default: "pending"
      t.text :proposed_diff
      t.text :blocked_reason
      t.text :review_notes
      t.string :resolution_source        # "auto", "llm", "manual"
      t.jsonb :llm_recommendation, default: {}
      t.datetime :next_eligible_at
      t.datetime :last_evaluated_at
      t.datetime :approved_at
      t.string :approved_by
      t.datetime :created_pr_at
      t.datetime :last_attempted_at

      t.timestamps
    end

    # One PatchBundle per branch + gem + current_version
    add_index :patch_bundles, [ :branch_target_id, :gem_name, :current_version ],
              unique: true, name: "index_patch_bundles_unique_per_branch_gem"
    add_index :patch_bundles, [ :gem_name, :base_branch, :state ]
    add_index :patch_bundles, [ :state, :last_evaluated_at ], name: "index_patch_bundles_for_reevaluation"
  end
end
