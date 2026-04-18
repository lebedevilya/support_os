class Customer < ApplicationRecord
  has_many :tickets, dependent: :destroy

  validates :email, presence: true, uniqueness: true
end
