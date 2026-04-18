class CreateManualKnowledgeEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :manual_knowledge_entries do |t|
      t.references :company, null: false, foreign_key: true
      t.string :title, null: false
      t.text :content, null: false
      t.string :status, null: false, default: "active"

      t.timestamps
    end
  end
end
