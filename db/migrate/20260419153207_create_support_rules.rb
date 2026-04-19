class CreateSupportRules < ActiveRecord::Migration[8.1]
  def change
    create_table :support_rules do |t|
      t.references :company, foreign_key: true
      t.string :name, null: false
      t.boolean :active, null: false, default: true
      t.integer :priority, null: false, default: 100
      t.string :match_type, null: false
      t.text :terms, null: false
      t.string :route, null: false
      t.string :category, null: false
      t.string :priority_level, null: false, default: "normal"
      t.decimal :confidence, precision: 4, scale: 2, null: false, default: 0.9
      t.text :reasoning_summary, null: false
      t.text :escalation_reason
      t.text :handoff_note
      t.timestamps
    end

    add_index :support_rules, [ :company_id, :active, :priority ]
  end
end
