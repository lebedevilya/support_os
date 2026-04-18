module Knowledge
  class Chunk < ApplicationRecord
    self.table_name = "knowledge_chunks"

    belongs_to :company
    belongs_to :source, class_name: "Knowledge::Source", foreign_key: :public_knowledge_source_id, optional: true, inverse_of: :chunks
    belongs_to :manual_entry, class_name: "Knowledge::ManualEntry", foreign_key: :manual_knowledge_entry_id, optional: true, inverse_of: :chunks

    validates :content, presence: true
  end
end
