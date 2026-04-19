class AgentRun < ApplicationRecord
  belongs_to :ticket
  has_many :tool_calls, dependent: :nullify

  validates :agent_name, :status, presence: true
end
