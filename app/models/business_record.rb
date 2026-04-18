class BusinessRecord < ApplicationRecord
  belongs_to :company

  validates :record_type, :external_id, :status, presence: true
end
