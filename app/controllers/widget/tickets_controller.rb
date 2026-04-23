module Widget
  class TicketsController < ApplicationController
    def new
      @ticket = Ticket.new
      @companies = Company.order(:name)
      @company = Company.find_by(id: params[:company_id])
      @ticket.company = @company if @company
    end

    def create
      @company = Company.find(ticket_params[:company_id])
      normalized_email = ticket_params[:email].to_s.downcase.strip
      @customer = Customer.find_or_initialize_by(email: normalized_email)
      @customer.validate

      unless @customer.errors.empty?
        @ticket = @company.tickets.build
        @ticket.company = @company
        @companies = Company.order(:name)

        return render_invalid_ticket
      end

      ActiveRecord::Base.transaction do
        customer = Customer.find_or_create_by!(email: normalized_email)

        @ticket = @company.tickets.create!(
          customer: customer,
          status: "new",
          channel: "widget",
          current_layer: "triage",
          processing: true
        )

        @ticket.messages.create!(role: "user", content: ticket_params[:content])
      end

      SupportPipelineJob.perform_later(@ticket.id)

      render :create, status: :ok
    end

    def chat
      @ticket = Ticket.find(params[:id])
      render turbo_stream: turbo_stream.replace(
        dom_id(@ticket, :chat),
        partial: "widget/tickets/chat",
        locals: { ticket: @ticket }
      )
    end

    def close
      @ticket = Ticket.find(params[:id])
      @ticket.update!(status: "resolved", human_handoff_available: false)

      respond_to do |format|
        format.turbo_stream { render :close, status: :ok }
        format.html { render :close, status: :ok }
      end
    end

    def handoff
      @ticket = Ticket.find(params[:id])
      @ticket.update!(
        status: "in_progress",
        current_layer: "human",
        manual_takeover: true,
        processing: false,
        human_handoff_available: false
      )

      respond_to do |format|
        format.turbo_stream { render :handoff, status: :ok }
        format.html { render :handoff, status: :ok }
      end
    end

    private

    def ticket_params
      params.expect(ticket: [ :company_id, :email, :content ])
    end

    def render_invalid_ticket
      if turbo_frame_request?
        render "widget/tickets/invalid", status: :unprocessable_entity
      else
        render :new, status: :unprocessable_entity
      end
    end
  end
end
