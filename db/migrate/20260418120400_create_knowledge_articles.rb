class CreateKnowledgeArticles < ActiveRecord::Migration[8.1]
  def change
    create_table :knowledge_articles do |t|
      t.references :company, null: false, foreign_key: true
      t.string :title, null: false
      t.string :slug
      t.string :category
      t.text :content, null: false

      t.timestamps
    end
  end
end
