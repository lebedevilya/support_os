class Company < ApplicationRecord
  has_many :knowledge_articles, dependent: :destroy
  has_many :knowledge_sources, class_name: "Knowledge::Source", dependent: :destroy
  has_many :manual_knowledge_entries, class_name: "Knowledge::ManualEntry", dependent: :destroy
  has_many :knowledge_chunks, class_name: "Knowledge::Chunk", dependent: :destroy
  has_many :tickets, dependent: :destroy
  has_many :business_records, dependent: :destroy

  validates :name, :slug, :support_email, presence: true
  validates :slug, uniqueness: true
end
