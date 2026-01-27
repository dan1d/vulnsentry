class CreateBundledAdvisories < ActiveRecord::Migration[8.1]
  def change
    create_table :bundled_advisories do |t|
      t.references :patch_bundle, null: false, foreign_key: true
      t.references :advisory, null: false, foreign_key: true
      t.string :suggested_fix_version    # What this CVE recommends
      t.boolean :included_in_fix, default: true, null: false
      t.text :exclusion_reason           # If not included, why

      t.timestamps
    end

    # Each advisory can only be linked to one PatchBundle per branch
    add_index :bundled_advisories, [:advisory_id, :patch_bundle_id], unique: true
  end
end
