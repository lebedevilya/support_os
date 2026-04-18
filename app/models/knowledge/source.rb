module Knowledge
  class Source < ApplicationRecord
    self.table_name = "public_knowledge_sources"

    belongs_to :company

    has_many :chunks, class_name: "Knowledge::Chunk", foreign_key: :public_knowledge_source_id, dependent: :destroy, inverse_of: :source

    validates :url, :source_kind, :status, presence: true
  end
end
