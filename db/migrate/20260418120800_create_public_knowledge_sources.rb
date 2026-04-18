class CreatePublicKnowledgeSources < ActiveRecord::Migration[8.1]
  def change
    create_table :public_knowledge_sources do |t|
      t.references :company, null: false, foreign_key: true
      t.string :url, null: false
      t.string :title
      t.string :source_kind, null: false
      t.string :status, null: false, default: "pending"
      t.text :extracted_text
      t.datetime :imported_at
      t.text :last_error

      t.timestamps
    end
  end
end
