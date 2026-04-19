module Widget
  class MessagesController < ApplicationController
    def create
      @ticket = Ticket.find(params[:ticket_id])
      content = message_params[:content].to_s.strip

      if @ticket.manual_takeover?
        @ticket.transaction do
          @ticket.messages.create!(role: "user", content: content)
          @ticket.update!(
            processing: false,
            status: "in_progress",
            current_layer: "human"
          )
        end
      else
        @ticket.update!(processing: true)
        @ticket.messages.create!(role: "user", content: content)
        SupportPipelineJob.perform_later(@ticket.id)
      end

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
