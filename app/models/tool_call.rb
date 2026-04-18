class ToolCall < ApplicationRecord
  belongs_to :ticket
  belongs_to :agent_run, optional: true

  validates :tool_name, :status, presence: true
end
