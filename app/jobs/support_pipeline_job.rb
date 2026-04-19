class SupportPipelineJob < ApplicationJob
  queue_as :default

  def perform(ticket_id)
    ticket = Ticket.find(ticket_id)
    SupportPipeline.new(ticket: ticket).call
    ticket.reload.update!(processing: false)
    ticket.broadcast_chat_update!
  rescue StandardError
    ticket&.update!(processing: false)
    ticket&.broadcast_chat_update!
    raise
  end
end
