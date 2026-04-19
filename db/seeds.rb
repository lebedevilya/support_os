ToolCall.delete_all
AgentRun.delete_all
Message.delete_all
Ticket.delete_all
BusinessRecord.delete_all
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
    name: "Supported country policy questions",
    active: true,
    priority: 20,
    match_type: "all_terms",
    terms: "support\ncanada",
    route: "specialist",
    category: "policy",
    priority_level: "normal",
    confidence: 0.88,
    reasoning_summary: "Supported-country policy questions can go to the policy specialist."
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
    company: aipassportphoto,
    name: "Operational and billing requests should not use public knowledge",
    active: true,
    priority: 90,
    match_type: "any_terms",
    terms: "paid\npayment\nrefund\nrejected\ndid not receive\ndidn't receive\ndownload link\nmy file\nmy order\nused the wrong email\nwrong email\ninvoice\nreceipt",
    route: "specialist",
    category: "other",
    priority_level: "normal",
    confidence: 0.9,
    reasoning_summary: "Operational and billing issues should not be answered from public knowledge.",
    blocks_public_knowledge: true
  },
  {
    company: nodes_garden,
    name: "Operational provisioning requests should not use public knowledge",
    active: true,
    priority: 90,
    match_type: "any_terms",
    terms: "my node\nprovisioning\nnode status\ninvoice\nreceipt",
    route: "specialist",
    category: "other",
    priority_level: "normal",
    confidence: 0.9,
    reasoning_summary: "Provisioning and operational node issues should not be answered from public knowledge.",
    blocks_public_knowledge: true
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

def import_public_site!(company:, root_url:)
  PublicKnowledge::SiteImporter.new(company: company, root_url: root_url).call
  puts "Imported public knowledge for #{company.name} from #{root_url}"
rescue StandardError => e
  warn "Public knowledge import failed for #{company.name} (#{root_url}): #{e.class}: #{e.message}"
end

import_public_site!(company: aipassportphoto, root_url: "https://www.aipassportphoto.co/")
import_public_site!(company: nodes_garden, root_url: "https://nodes.garden/")

[
  {
    company: aipassportphoto,
    record_type: "photo_request",
    external_id: "APP-1001",
    customer_email: "anna@example.com",
    status: "completed",
    payload: {
      asset_delivery: "sent",
      download_url: "https://example.test/download/APP-1001"
    }
  },
  {
    company: aipassportphoto,
    record_type: "photo_request",
    external_id: "APP-1002",
    customer_email: "mark@example.com",
    status: "processing",
    payload: {
      asset_delivery: "pending"
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
      last_error: nil
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
      last_error: nil
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
  content: "Do you support Canada passport photos?"
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
