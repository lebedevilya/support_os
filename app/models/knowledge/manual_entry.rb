module Knowledge
  class ManualEntry < ApplicationRecord
    self.table_name = "manual_knowledge_entries"

    belongs_to :company

    has_many :chunks, class_name: "Knowledge::Chunk", foreign_key: :manual_knowledge_entry_id, dependent: :destroy, inverse_of: :manual_entry

    validates :title, :content, :status, presence: true
  end
end
