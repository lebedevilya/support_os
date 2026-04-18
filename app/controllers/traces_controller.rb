class TracesController < ApplicationController
  def show
    @ticket = Ticket.includes(:agent_runs, :tool_calls).find(params[:ticket_id])
  end
end
