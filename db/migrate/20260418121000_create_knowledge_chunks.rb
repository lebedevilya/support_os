class CreateKnowledgeChunks < ActiveRecord::Migration[8.1]
  def change
    create_table :knowledge_chunks do |t|
      t.references :company, null: false, foreign_key: true
      t.references :public_knowledge_source, foreign_key: true
      t.references :manual_knowledge_entry, foreign_key: true
      t.text :content, null: false
      t.integer :position, null: false, default: 0
      t.integer :token_estimate, null: false, default: 0

      t.timestamps
    end
  end
end
