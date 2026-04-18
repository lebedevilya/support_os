class CreateAgentRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_runs do |t|
      t.references :ticket, null: false, foreign_key: true
      t.string :agent_name, null: false
      t.string :status, null: false
      t.string :decision
      t.decimal :confidence, precision: 4, scale: 2
      t.text :input_snapshot
      t.text :output_snapshot
      t.text :reasoning_summary

      t.timestamps
    end
  end
end
