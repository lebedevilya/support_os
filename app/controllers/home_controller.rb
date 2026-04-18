class HomeController < ApplicationController
  def index
    @companies = Company.order(:name)
    @trace_ticket = Ticket.order(updated_at: :desc).first
    return if @companies.any?

    @companies = [
      Company.new(name: "AI Passport Photo", description: "Passport and visa photo support"),
      Company.new(name: "nodes.garden", description: "Node deployment and provisioning support")
    ]
  end
end
