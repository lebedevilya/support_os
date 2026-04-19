class AddBlocksPublicKnowledgeToSupportRules < ActiveRecord::Migration[8.1]
  def change
    add_column :support_rules, :blocks_public_knowledge, :boolean, default: false, null: false
    add_index :support_rules, [ :company_id, :active, :blocks_public_knowledge, :priority ], name: "index_support_rules_on_company_active_blockers_priority"
  end
end
