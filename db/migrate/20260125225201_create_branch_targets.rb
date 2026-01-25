class CreateBranchTargets < ActiveRecord::Migration[8.1]
  def change
    create_table :branch_targets do |t|
      t.string :name, null: false
      t.boolean :enabled, null: false, default: true
      t.string :maintenance_status, null: false
      t.text :source_url
      t.datetime :last_seen_at
      t.datetime :last_checked_at

      t.timestamps
    end

    add_index :branch_targets, :name, unique: true
  end
end
