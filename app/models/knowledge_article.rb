class KnowledgeArticle < ApplicationRecord
  belongs_to :company

  validates :title, :content, presence: true
end
