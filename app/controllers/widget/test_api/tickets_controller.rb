module Widget
  module TestApi
    class TicketsController < ApplicationController
      skip_forgery_protection
      before_action :authenticate_regression_api!
      before_action :set_ticket, only: [ :show, :close, :create_message ]

      def create
        company = Company.find_by!(slug: params[:company_slug])
        normalized_email = params[:email].to_s.downcase.strip
        content = params[:content].to_s.strip

        customer = Customer.find_or_create_by!(email: normalized_email)

        ticket = nil
        ActiveRecord::Base.transaction do
          ticket = company.tickets.create!(
            customer: customer,
            status: "new",
            channel: "widget",
            current_layer: "triage",
            processing: true
          )
          ticket.messages.create!(role: "user", content: content)
        end

        SupportPipelineJob.perform_later(ticket.id)

        render json: { ticket: serialized_ticket(ticket.reload) }, status: :created
      end

      def show
        render json: { ticket: serialized_ticket(@ticket) }, status: :ok
      end

      def create_message
        content = params[:content].to_s.strip

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

        render json: { ticket: serialized_ticket(@ticket.reload) }, status: :created
      end

      def close
        @ticket.update!(status: "resolved", human_handoff_available: false)

        render json: { ticket: serialized_ticket(@ticket.reload) }, status: :ok
      end

      private

      def authenticate_regression_api!
        expected_token = Rails.application.credentials.dig(:regression_api, :token).to_s
        provided_token = request.authorization.to_s.delete_prefix("Bearer ").strip

        return if expected_token.present? && ActiveSupport::SecurityUtils.secure_compare(provided_token, expected_token)

        head :unauthorized
      end

      def set_ticket
        @ticket = Ticket.find(params[:id])
      end

      def serialized_ticket(ticket)
        messages = ticket.messages.order(:created_at)

        {
          id: ticket.id,
          company_slug: ticket.company.slug,
          customer_email: ticket.customer.email,
          status: ticket.status,
          category: ticket.category,
          priority: ticket.priority,
          current_layer: ticket.current_layer,
          processing: ticket.processing,
          manual_takeover: ticket.manual_takeover,
          human_handoff_available: ticket.human_handoff_available,
          latest_user_message: messages.where(role: "user").last&.content,
          latest_assistant_message: messages.where(role: "assistant").last&.content,
          messages: messages.map { |message| serialized_message(message) }
        }
      end

      def serialized_message(message)
        {
          id: message.id,
          role: message.role,
          content: message.content,
          created_at: message.created_at.iso8601
        }
      end
    end
  end
end
