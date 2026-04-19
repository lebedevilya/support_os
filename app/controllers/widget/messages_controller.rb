module Widget
  class MessagesController < ApplicationController
    def create
      @ticket = Ticket.find(params[:ticket_id])
      @ticket.update!(processing: true)
      @ticket.messages.create!(role: "user", content: message_params[:content])
      SupportPipelineJob.perform_later(@ticket.id)

      respond_to do |format|
        format.turbo_stream { render :create, status: :ok }
        format.html { render :create, status: :ok }
      end
    end

    private

    def message_params
      params.expect(message: [ :content ])
    end
  end
end
