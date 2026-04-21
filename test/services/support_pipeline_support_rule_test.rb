require "test_helper"

class SupportPipelineSupportRuleTest < ActiveSupport::TestCase
  test "offers a manual human handoff for an embassy refund dispute through a support rule" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )
    customer = Customer.create!(email: "anna@example.com")

    SupportRule.create!(
      name: "Embassy refund dispute",
      active: true,
      priority: 10,
      match_type: "all_terms",
      terms: "embassy\nrefund",
      route: "escalate",
      category: "refund",
      priority_level: "high",
      confidence: 0.92,
      reasoning_summary: "Embassy rejection disputes require human review.",
      escalation_reason: "Refund dispute requires human review.",
      handoff_note: "Escalated for human review because the customer reports an embassy rejection dispute."
    )

    ticket = company.tickets.create!(
      customer: customer,
      status: "new",
      channel: "widget",
      current_layer: "triage"
    )
    ticket.messages.create!(role: "user", content: "My photo was rejected by the embassy and I want a refund right now")

    SupportPipeline.new(ticket: ticket, llm_client: false).call

    ticket.reload

    assert_equal "awaiting_customer", ticket.status
    assert_equal "triage", ticket.current_layer
    assert_equal false, ticket.manual_takeover
    assert_equal true, ticket.human_handoff_available
    assert_equal "refund", ticket.category
    assert_equal 1, ticket.agent_runs.count
    assert_equal "assistant", ticket.messages.order(:created_at).last.role
    assert_includes ticket.messages.order(:created_at).last.content.downcase, "human"

    triage_run = ticket.agent_runs.order(:created_at).first
    triage_snapshot = JSON.parse(triage_run.output_snapshot)

    assert_equal "support_rule", triage_snapshot.fetch("source")
    assert_equal "Embassy refund dispute", triage_snapshot.fetch("matched_rule_name")
  end

end
