ToolCall.delete_all
AgentRun.delete_all
Message.delete_all
Ticket.delete_all
BusinessRecord.delete_all
ActsAsTaggableOn::Tagging.delete_all
ActsAsTaggableOn::Tag.delete_all
Knowledge::Chunk.delete_all
Knowledge::ManualEntry.delete_all
Knowledge::Source.delete_all
KnowledgeArticle.delete_all
SupportRule.delete_all
Customer.delete_all
Company.delete_all

aipassportphoto = Company.create!(
  name: "AI Passport Photo",
  slug: "aipassportphoto",
  description: "AI-generated passport and visa photo support.",
  support_email: "help@aipassportphoto.co"
)

nodes_garden = Company.create!(
  name: "nodes.garden",
  slug: "nodes-garden",
  description: "Node deployment, provisioning, and status support.",
  support_email: "support@nodes.garden"
)

[
  {
    name: "Embassy refund dispute",
    active: true,
    priority: 10,
    match_type: "all_terms",
    terms: "embassy\nrefund",
    route: "escalate",
    category: "refund",
    priority_level: "high",
    confidence: 0.92,
    reasoning_summary: "Embassy or government rejection disputes require human review.",
    escalation_reason: "Refund dispute requires human review.",
    handoff_note: "Escalated for human review because the customer reports an embassy rejection dispute."
  },
  {
    company: aipassportphoto,
    name: "Missing asset delivery questions",
    active: true,
    priority: 20,
    match_type: "any_terms",
    terms: "did not receive\ndidn't receive",
    route: "specialist",
    category: "delivery",
    priority_level: "normal",
    confidence: 0.82,
    reasoning_summary: "Missing asset questions can go to the delivery specialist."
  },
  {
    company: aipassportphoto,
    name: "Download link resend requests",
    active: true,
    priority: 18,
    match_type: "all_terms",
    terms: "resend\ndownload link",
    route: "specialist",
    category: "delivery",
    priority_level: "high",
    confidence: 0.9,
    reasoning_summary: "Download-link resend requests should go to the delivery specialist."
  },
  {
    company: aipassportphoto,
    name: "Photo request status questions",
    active: true,
    priority: 19,
    match_type: "all_terms",
    terms: "status\nphoto request",
    route: "specialist",
    category: "delivery",
    priority_level: "normal",
    confidence: 0.86,
    reasoning_summary: "Photo request status questions should go to the delivery specialist."
  },
  {
    company: nodes_garden,
    name: "Provisioning status questions",
    active: true,
    priority: 20,
    match_type: "any_terms",
    terms: "provisioning\nnode status",
    route: "specialist",
    category: "technical",
    priority_level: "normal",
    confidence: 0.84,
    reasoning_summary: "Provisioning and node-status questions can go to the technical specialist."
  },
  {
    company: nodes_garden,
    name: "Node reboot requests",
    active: true,
    priority: 18,
    match_type: "all_terms",
    terms: "reboot\nnode",
    route: "specialist",
    category: "technical",
    priority_level: "high",
    confidence: 0.9,
    reasoning_summary: "Explicit reboot requests should go to the technical specialist."
  }
].each do |attributes|
  SupportRule.create!(attributes)
end

[
  {
    company: aipassportphoto,
    title: "Supported Countries",
    category: "policy",
    content: "We support passport and visa photo formats for Canada, the US, the UK, India, Schengen, and Australia."
  },
  {
    company: aipassportphoto,
    title: "Refund Policy",
    category: "refund",
    content: "Embassy or government rejection disputes require human review before any refund decision."
  },
  {
    company: aipassportphoto,
    title: "Delivery Timing",
    category: "delivery",
    content: "Most photo requests complete in under two minutes, but heavy load can delay delivery."
  },
  {
    company: aipassportphoto,
    title: "Privacy",
    category: "policy",
    content: "Photo requests are deleted after 30 days unless a customer asks for earlier deletion."
  },
  {
    company: nodes_garden,
    title: "Provisioning Lifecycle",
    category: "technical",
    content: "New deployments begin in provisioning, then move to syncing, healthy, or failed depending on node health."
  },
  {
    company: nodes_garden,
    title: "Deployment Delays",
    category: "technical",
    content: "Provisioning delays can happen while infrastructure boots or while the node catches up to chain state."
  },
  {
    company: nodes_garden,
    title: "Retry Policy",
    category: "technical",
    content: "Failed deployments can be retried after the last error is inspected."
  },
  {
    company: nodes_garden,
    title: "Billing and Credits",
    category: "billing",
    content: "Billing is usage-backed, but provisioning questions should be resolved before credit reviews."
  }
].each do |attributes|
  KnowledgeArticle.create!(attributes)
end

[
  {
    company: aipassportphoto,
    title: "Pricing",
    content: "AI Passport Photo offers a $4.99 Image Only option and a $7.99 Image + Print PDF option."
  },
  {
    company: aipassportphoto,
    title: "Image Only package",
    content: "The $4.99 Image Only option includes a high-resolution digital image, 300 DPI quality, and a file ready for upload."
  },
  {
    company: aipassportphoto,
    title: "Image plus Print PDF package",
    content: "The $7.99 Image + Print PDF option includes a high-resolution digital image, 300 DPI quality, and a print-ready PDF with 4 photos and cutting guides."
  },
  {
    company: aipassportphoto,
    title: "Turnaround time",
    content: "Most passport photo requests are completed in under 60 seconds. In heavier traffic, delivery can take up to 2 minutes."
  },
  {
    company: aipassportphoto,
    title: "Money-back guarantee",
    content: "AI Passport Photo offers a 100% money-back guarantee if a passport photo is rejected for compliance reasons. Rejection and refund disputes are still reviewed by human support before a final decision."
  },
  {
    company: aipassportphoto,
    title: "Acceptance and compliance",
    content: "AI Passport Photo says its photos meet ICAO 9303 specifications, U.S. Department of State requirements, UK HMPO specifications, and ISO/IEC 19794-5 formatting. The site also says photos are accepted at USPS, DMV, and embassies."
  },
  {
    company: aipassportphoto,
    title: "Camera and lighting",
    content: "Customers do not need a professional camera or special lighting. The site says any selfie works and can be taken from a phone or computer."
  },
  {
    company: aipassportphoto,
    title: "Phone upload and printing",
    content: "Customers can upload a selfie from a phone or computer. AI Passport Photo provides a high-resolution digital file and a print-ready PDF option for printing at home."
  },
  {
    company: aipassportphoto,
    title: "Privacy and retention",
    content: "AI Passport Photo says customer photos are stored only as needed to provide the service and are deleted after 30 days unless the customer asks for earlier deletion."
  },
  {
    company: aipassportphoto,
    title: "Deletion policy",
    content: "AI Passport Photo says uploaded customer photos are deleted after 30 days unless the customer asks for earlier deletion."
  },
  {
    company: aipassportphoto,
    title: "Payment security",
    content: "AI Passport Photo says payments are processed securely through Stripe and the site uses 256-bit SSL encryption."
  },
  {
    company: aipassportphoto,
    title: "Supported countries",
    content: "AI Passport Photo says it supports the US, UK, Canada, Germany, the European Union, Switzerland, India, Australia, Japan, China, Brazil, and more international formats."
  },
  {
    company: aipassportphoto,
    title: "Canada passport photos",
    content: "AI Passport Photo says it supports Canada passport photos in a 50 x 70 mm format."
  },
  {
    company: aipassportphoto,
    title: "UK visa and passport photos",
    content: "AI Passport Photo says it supports UK requirements and shows UK passport photo support on the site. The site also says it supports passport and visa photo formats for the UK."
  },
  {
    company: aipassportphoto,
    title: "Support contact",
    content: "Customers can contact AI Passport Photo support through the website contact page or by emailing help@aipassportphoto.co."
  },
  {
    company: nodes_garden,
    title: "Provisioning lifecycle",
    content: "New nodes.garden deployments move through provisioning, syncing, and healthy states. Provisioning delays can happen while infrastructure boots or while the node catches up to chain state."
  },
  {
    company: nodes_garden,
    title: "Provisioning delays",
    content: "If a node stays in provisioning, the most common causes are infrastructure startup delay or slow chain synchronization. Human support should review cases that stay stuck unusually long."
  },
  {
    company: nodes_garden,
    title: "Deployment retries",
    content: "Failed deployments can be retried after the most recent error is inspected. The system should not claim a retry happened unless the trace includes an explicit retry action."
  },
  {
    company: nodes_garden,
    title: "Billing basics",
    content: "nodes.garden billing is usage-backed. Provisioning issues should be resolved before reviewing credits or billing adjustments."
  },
  {
    company: nodes_garden,
    title: "Support contact",
    content: "Customers can contact nodes.garden support through the main website support path or by emailing support@nodes.garden."
  }
].each do |attributes|
  Knowledge::ManualEntry.create!(attributes.merge(status: "active"))
end

def import_public_site!(company:, root_url:)
  PublicKnowledge::SiteImporter.new(company: company, root_url: root_url).call
  puts "Imported public knowledge for #{company.name} from #{root_url}"
rescue StandardError => e
  warn "Public knowledge import failed for #{company.name} (#{root_url}): #{e.class}: #{e.message}"
end

import_public_site!(company: aipassportphoto, root_url: "https://www.aipassportphoto.co/")
import_public_site!(company: nodes_garden, root_url: "https://nodes.garden/")

%w[
  policy
  supported-country
  public-knowledge
  delivery
  asset-delivery
  refund
  embassy-rejection
  human-review
  technical
  provisioning
  node
  missing-record
  llm-failure
  payment
  discount
].each do |name|
  ActsAsTaggableOn::Tag.find_or_create_by!(name: name)
end

[
  {
    company: aipassportphoto,
    record_type: "photo_request",
    external_id: "APP-1001",
    customer_email: "anna@example.com",
    status: "completed",
    payload: {
      asset_delivery: "sent",
      download_url: "https://example.test/download/APP-1001",
      resend_allowed: true
    }
  },
  {
    company: aipassportphoto,
    record_type: "photo_request",
    external_id: "APP-1002",
    customer_email: "mark@example.com",
    status: "processing",
    payload: {
      asset_delivery: "pending",
      resend_allowed: false
    }
  },
  {
    company: aipassportphoto,
    record_type: "photo_request",
    external_id: "APP-1003",
    customer_email: "sara@example.com",
    status: "completed",
    payload: {
      asset_delivery: "sent",
      download_url: "https://example.test/download/APP-1003",
      resend_allowed: true
    }
  },
  {
    company: nodes_garden,
    record_type: "node_deployment",
    external_id: "ND-1001",
    customer_email: "operator@example.com",
    status: "provisioning",
    payload: {
      node_name: "validator-1",
      last_error: nil,
      reboot_allowed: true
    }
  },
  {
    company: nodes_garden,
    record_type: "node_deployment",
    external_id: "ND-1002",
    customer_email: "builder@example.com",
    status: "healthy",
    payload: {
      node_name: "archive-1",
      last_error: nil,
      reboot_allowed: false
    }
  }
].each do |attributes|
  BusinessRecord.create!(attributes)
end

def seed_ticket!(company:, email:, content:)
  customer = Customer.find_or_create_by!(email: email)
  ticket = company.tickets.create!(
    customer: customer,
    status: "new",
    channel: "widget",
    current_layer: "triage"
  )
  ticket.messages.create!(role: "user", content: content)
  SupportPipeline.new(ticket: ticket).call
  ticket
end

seed_ticket!(
  company: aipassportphoto,
  email: "anna@example.com",
  content: "I paid but did not receive my file"
)

seed_ticket!(
  company: aipassportphoto,
  email: "review@example.com",
  content: "Can I make a picture for UK visa?"
)

seed_ticket!(
  company: aipassportphoto,
  email: "timing@example.com",
  content: "How long does it take?"
)

seed_ticket!(
  company: aipassportphoto,
  email: "refund@example.com",
  content: "My photo was rejected by the embassy and I want a refund right now"
)

seed_ticket!(
  company: nodes_garden,
  email: "operator@example.com",
  content: "My node is still provisioning after 20 minutes"
)

seed_ticket!(
  company: aipassportphoto,
  email: "sara@example.com",
  content: "I did not receive my file, resend the download link"
)

seed_ticket!(
  company: nodes_garden,
  email: "operator@example.com",
  content: "Reboot my node"
)

seed_ticket!(
  company: nodes_garden,
  email: "billing@example.com",
  content: "How does billing work?"
)

seed_ticket!(
  company: nodes_garden,
  email: "human@example.com",
  content: "Connect me to a human in this chat"
)
