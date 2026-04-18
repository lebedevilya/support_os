class CreateTickets < ActiveRecord::Migration[8.1]
  def change
    create_table :tickets do |t|
      t.references :company, null: false, foreign_key: true
      t.references :customer, null: false, foreign_key: true
      t.string :status, null: false
      t.string :category
      t.string :priority
      t.string :channel, null: false
      t.decimal :last_confidence, precision: 4, scale: 2
      t.string :current_layer, null: false
      t.text :summary
      t.text :escalation_reason
      t.text :handoff_note

      t.timestamps
    end
  end
end
