class CreateSystemEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :system_events do |t|
      t.string :kind, null: false
      t.string :status, null: false
      t.text :message
      t.jsonb :payload, null: false, default: {}
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :system_events, [ :kind, :occurred_at ]
    add_index :system_events, [ :status, :occurred_at ]
  end
end
