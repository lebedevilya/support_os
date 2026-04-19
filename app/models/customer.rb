class Customer < ApplicationRecord
  EMAIL_FORMAT = URI::MailTo::EMAIL_REGEXP

  has_many :tickets, dependent: :destroy

  validates :email, presence: true, uniqueness: true
  validates :email, format: { with: EMAIL_FORMAT }
end
