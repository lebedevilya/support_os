ToolCall.delete_all
AgentRun.delete_all
Message.delete_all
Ticket.delete_all
BusinessRecord.delete_all
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
    url: "https://www.aipassportphoto.co/",
    title: "Homepage",
    source_kind: "website_page",
    extracted_text: "Under 60 seconds. Upload your photo, our AI processes it instantly, and you can download or print your compliant passport photo right away. Passport and visa photos for Canada, the US, the UK, India, Schengen, and Australia."
  },
  {
    company: aipassportphoto,
    url: "https://www.aipassportphoto.co/guarantee",
    title: "Guarantee",
    source_kind: "website_page",
    extracted_text: "Money-back guarantee applies when the final photo does not meet the supported document standards. Embassy or government rejection disputes may require manual review."
  },
  {
    company: aipassportphoto,
    url: "https://www.aipassportphoto.co/privacy",
    title: "Privacy",
    source_kind: "website_page",
    extracted_text: "Uploaded photos are deleted after 30 days unless a customer asks for earlier deletion."
  },
  {
    company: aipassportphoto,
    url: "https://www.aipassportphoto.co/contact",
    title: "Contact",
    source_kind: "website_page",
    extracted_text: "Contact support at help@aipassportphoto.co for questions that require manual assistance."
  },
  {
    company: nodes_garden,
    url: "https://www.nodes.garden/",
    title: "Homepage",
    source_kind: "website_page",
    extracted_text: "nodes.garden helps teams deploy and operate nodes with clear provisioning and health visibility. Provisioning can take time while infrastructure boots and the node catches up to chain state."
  },
  {
    company: nodes_garden,
    url: "https://www.nodes.garden/contact",
    title: "Contact",
    source_kind: "website_page",
    extracted_text: "Contact support at support@nodes.garden when deployment issues require manual review."
  }
].each do |attributes|
  source = Knowledge::Source.create!(
    company: attributes[:company],
    url: attributes[:url],
    title: attributes[:title],
    source_kind: attributes[:source_kind],
    status: "imported",
    imported_at: Time.current,
    extracted_text: attributes[:extracted_text]
  )

  PublicKnowledge::Chunker.new(text: source.extracted_text).call.each_with_index do |chunk, index|
    source.chunks.create!(
      company: source.company,
      content: chunk,
      position: index,
      token_estimate: (chunk.split.size * 1.3).ceil
    )
  end
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
