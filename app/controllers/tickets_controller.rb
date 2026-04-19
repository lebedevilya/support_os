class TicketsController < ApplicationController
  def index
    @tickets = Ticket.includes(:company, :customer)
      .order(Arel.sql("CASE WHEN status = 'escalated' THEN 0 ELSE 1 END, updated_at DESC"))
  end

  def show
    @ticket = Ticket.includes(:company, :customer, :messages, :agent_runs, :tool_calls).find(params[:id])
  end

  def reply
    @ticket = Ticket.find(params[:id])
    content = reply_params[:content].to_s.strip

    if content.blank?
      redirect_to ticket_path(@ticket), alert: "Reply can't be blank."
      return
    end

    @ticket.transaction do
      @ticket.messages.create!(role: "human", content: content)
      @ticket.update!(
        status: "awaiting_customer",
        current_layer: "human",
        escalation_reason: nil,
        handoff_note: nil
      )
    end

    redirect_to ticket_path(@ticket)
  end

  private

  def reply_params
    params.expect(message: [ :content ])
  end
end
