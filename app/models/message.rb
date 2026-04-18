class Message < ApplicationRecord
  belongs_to :ticket

  enum :role, {
    user: "user",
    assistant: "assistant",
    human: "human",
    system: "system"
  }

  validates :role, :content, presence: true
end
