class CreateAdvisories < ActiveRecord::Migration[8.1]
  def change
    create_table :advisories do |t|
      t.string :gem_name, null: false
      t.string :cve
      t.string :source, null: false
      t.text :advisory_url
      t.text :affected_requirement
      t.string :fixed_version
      t.string :severity
      t.jsonb :raw, null: false, default: {}
      t.datetime :published_at
      t.datetime :withdrawn_at
      t.string :fingerprint, null: false

      t.timestamps
    end

    add_index :advisories, :fingerprint, unique: true
    add_index :advisories, :gem_name
  end
end
