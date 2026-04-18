class TicketsController < ApplicationController
  def index
    @tickets = Ticket.includes(:company, :customer).order(updated_at: :desc)
  end

  def show
    @ticket = Ticket.includes(:company, :customer, :messages, :agent_runs, :tool_calls).find(params[:id])
  end
end
