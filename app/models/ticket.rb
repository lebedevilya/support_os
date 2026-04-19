class Ticket < ApplicationRecord
  belongs_to :company
  belongs_to :customer

  has_many :messages, dependent: :destroy
  has_many :agent_runs, dependent: :destroy
  has_many :tool_calls, dependent: :destroy

  enum :channel, {
    widget: "widget"
  }

  validates :status, :channel, :current_layer, presence: true

  def broadcast_chat_update!
    broadcast_replace_to(
      self,
      target: ActionView::RecordIdentifier.dom_id(self, :chat),
      partial: "widget/tickets/chat",
      locals: { ticket: self }
    )
  end
end
