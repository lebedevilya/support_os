module Widget
  class MessagesController < ApplicationController
    def create
      @ticket = Ticket.find(params[:ticket_id])
      @ticket.messages.create!(role: "user", content: message_params[:content])
      SupportPipeline.new(ticket: @ticket).call

      render :create, status: :ok
    end

    private

    def message_params
      params.expect(message: [ :content ])
    end
  end
end
