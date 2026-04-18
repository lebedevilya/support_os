class CreateToolCalls < ActiveRecord::Migration[8.1]
  def change
    create_table :tool_calls do |t|
      t.references :ticket, null: false, foreign_key: true
      t.references :agent_run, foreign_key: true
      t.string :tool_name, null: false
      t.string :status, null: false
      t.text :input_payload
      t.text :output_payload

      t.timestamps
    end
  end
end
