module Widget
  class TicketsController < ApplicationController
    def new
      @ticket = Ticket.new
      @companies = Company.order(:name)
    end

    def create
      ActiveRecord::Base.transaction do
        company = Company.find(ticket_params[:company_id])
        customer = Customer.find_or_create_by!(email: ticket_params[:email].downcase.strip)

        @ticket = company.tickets.create!(
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

    def close
      @ticket = Ticket.find(params[:id])
      @ticket.update!(status: "resolved")

      respond_to do |format|
        format.turbo_stream { render :close, status: :ok }
        format.html { render :close, status: :ok }
      end
    end

    private

    def ticket_params
      params.expect(ticket: [ :company_id, :email, :content ])
    end
  end
end
