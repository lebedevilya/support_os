class Company < ApplicationRecord
  has_many :knowledge_articles, dependent: :destroy
  has_many :tickets, dependent: :destroy
  has_many :business_records, dependent: :destroy

  validates :name, :slug, :support_email, presence: true
  validates :slug, uniqueness: true
end
