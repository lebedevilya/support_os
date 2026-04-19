class TicketsController < ApplicationController
  def index
    @companies = Company.order(:name)
    @statuses = Ticket.distinct.order(:status).pluck(:status).compact
    @tags = ActsAsTaggableOn::Tag.for_context(:tags).order(:name)

    base_scope = Ticket.includes(:company, :customer).distinct
    filtered_scope = apply_filters(base_scope)

    @pagy, @tickets = pagy(
      filtered_scope.order(Arel.sql("CASE WHEN status = 'escalated' THEN 0 ELSE 1 END, updated_at DESC")),
      limit: 10
    )
    @total_tickets_count = base_scope.count
    @company_counts = Company.left_joins(:tickets).group("companies.id").order(:name).count("tickets.id")
    @status_counts = Ticket.group(:status).count
    @tag_counts = Ticket.tag_counts_on(:tags).index_by(&:name)
  end

  def show
    @ticket = Ticket.includes(:company, :customer, :messages, :agent_runs, :tool_calls).find(params[:id])
  end

  def reply
    @ticket = Ticket.find(params[:id])
    content = reply_params[:content].to_s.strip

    if content.blank?
      redirect_to ticket_path(@ticket, anchor: "support-reply"), alert: "Reply can't be blank."
      return
    end

    @ticket.transaction do
      @ticket.messages.create!(role: "human", content: content)
      @ticket.update!(
        status: "awaiting_customer",
        current_layer: "human",
        manual_takeover: true,
        escalation_reason: nil,
        handoff_note: nil
      )
    end

    redirect_to ticket_path(@ticket, anchor: "support-reply")
  end

  private

  def apply_filters(scope)
    filtered = scope
    filtered = filtered.where(company_id: params[:company_id]) if params[:company_id].present?
    filtered = filtered.where(status: params[:status]) if params[:status].present?
    filtered = filtered.tagged_with(params[:tag]) if params[:tag].present?
    filtered
  end

  def reply_params
    params.expect(message: [ :content ])
  end
end
