class CompaniesController < ApplicationController
  before_action :set_company

  def show
    @landing = landing_content_for(@company)
    @ticket = Ticket.new(company: @company)
  end

  private

  def set_company
    @company = Company.find_by!(slug: params[:slug])
  end

  def landing_content_for(company)
    case company.slug
    when "aipassportphoto"
      {
        eyebrow: "AI Passport Photo",
        hero_title: "Passport Photos That Pass. Guaranteed, in Seconds.",
        hero_copy: "Upload a selfie, let the AI clean the background, and get a compliant passport or visa photo without hunting for a studio.",
        primary_cta: "Try Free",
        secondary_cta: "See requirements",
        stats: [
          [ "100+", "country templates" ],
          [ "Under 60s", "average turnaround" ],
          [ "Guaranteed", "compliance promise" ]
        ],
        features: [
          "Automatic background removal and crop adjustment",
          "Templates for US, UK, Canada, and 100+ countries",
          "Instant download and print-ready delivery"
        ],
        spotlight_title: "Built for the annoying part of travel prep",
        spotlight_copy: "No pharmacies. No booth retakes. No guesswork on size, background, or lighting."
      }
    when "nodes-garden"
      {
        eyebrow: "nodes.garden",
        hero_title: "Launch self-hosted nodes without babysitting infra.",
        hero_copy: "Deploy blockchain and infrastructure nodes through a cleaner control plane, with monitored provisioning and support when things drift.",
        primary_cta: "Explore plans",
        secondary_cta: "Read FAQ",
        stats: [
          [ "Fast setup", "guided provisioning flow" ],
          [ "Clear billing", "subscription-backed plans" ],
          [ "Human fallback", "support for stuck deployments" ]
        ],
        features: [
          "Provision popular node setups from a guided dashboard",
          "Track deployment status without watching raw logs",
          "Escalate edge cases when automation is not enough"
        ],
        spotlight_title: "Infrastructure products die on trust",
        spotlight_copy: "The page is simple on purpose: clear offering, clear expectations, and support visible from the first screen."
      }
    else
      {
        eyebrow: company.name,
        hero_title: company.name,
        hero_copy: company.description.to_s,
        primary_cta: "Get started",
        secondary_cta: "Learn more",
        stats: [],
        features: [],
        spotlight_title: "Customer support",
        spotlight_copy: "Start a conversation through the widget."
      }
    end
  end
end
