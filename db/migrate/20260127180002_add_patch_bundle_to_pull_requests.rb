class AddPatchBundleToPullRequests < ActiveRecord::Migration[8.1]
  def change
    # Add optional reference to patch_bundle (for transition period)
    add_reference :pull_requests, :patch_bundle, null: true, foreign_key: true

    # Add index for looking up PRs by patch_bundle
    add_index :pull_requests, :patch_bundle_id, unique: true, where: "patch_bundle_id IS NOT NULL",
              name: "index_pull_requests_on_patch_bundle_unique"
  end
end
