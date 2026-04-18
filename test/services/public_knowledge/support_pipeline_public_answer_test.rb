require "test_helper"

class SupportPipelinePublicAnswerTest < ActiveSupport::TestCase
  test "answers faq-style question from public knowledge at triage level" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )
    customer = Customer.create!(email: "review@example.com")

    source = Knowledge::Source.create!(
      company: company,
      url: "https://www.aipassportphoto.co/",
      title: "Homepage",
      source_kind: "website_page",
      status: "imported",
      extracted_text: "Under 60 seconds. Upload your photo, our AI processes it instantly, and you can download or print your compliant passport photo right away."
    )
    source.chunks.create!(
      company: company,
      content: "Under 60 seconds. Upload your photo, our AI processes it instantly, and you can download or print your compliant passport photo right away.",
      position: 0,
      token_estimate: 24
    )

    ticket = company.tickets.create!(
      customer: customer,
      status: "new",
      channel: "widget",
      current_layer: "triage"
    )
    ticket.messages.create!(role: "user", content: "How long does it take?")

    SupportPipeline.new(ticket: ticket, llm_client: false).call

    ticket.reload

    assert_equal "resolved", ticket.status
    assert_equal "triage", ticket.current_layer
    assert_equal 1, ticket.agent_runs.count
    assert_equal [ "user", "assistant" ], ticket.messages.order(:created_at).pluck(:role)
    assert_includes ticket.messages.order(:created_at).last.content, "Under 60 seconds"
    assert_equal "policy", ticket.category
  end
end
