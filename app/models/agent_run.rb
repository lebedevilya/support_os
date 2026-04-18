class AgentRun < ApplicationRecord
  belongs_to :ticket

  validates :agent_name, :status, presence: true
end
