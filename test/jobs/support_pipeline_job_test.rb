require "test_helper"

class SupportPipelineJobTest < ActiveJob::TestCase
  test "processes the ticket, clears processing, and appends the assistant reply" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )
    customer = Customer.create!(email: "anna@example.com")

    SupportRule.create!(
      company: company,
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
    )

    BusinessRecord.create!(
      company: company,
      record_type: "photo_request",
      external_id: "APP-1001",
      customer_email: "anna@example.com",
      status: "completed",
      payload: {}
    )

    ticket = company.tickets.create!(
      customer: customer,
      status: "new",
      channel: "widget",
      current_layer: "triage",
      processing: true
    )
    ticket.messages.create!(role: "user", content: "I paid but did not receive my file")

    original_builder = LLM::Client.method(:build_from_env)
    LLM::Client.singleton_class.define_method(:build_from_env) { nil }

    begin
      SupportPipelineJob.perform_now(ticket.id)
    ensure
      LLM::Client.singleton_class.define_method(:build_from_env) do
        original_builder.call
      end
    end

    ticket.reload

    assert_equal false, ticket.processing
    assert_equal "awaiting_customer", ticket.status
    assert_equal [ "user", "assistant" ], ticket.messages.order(:created_at).pluck(:role)
    assert_equal 2, ticket.agent_runs.count
  end

  test "does not process a manually owned ticket" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )
    customer = Customer.create!(email: "anna@example.com")

    ticket = company.tickets.create!(
      customer: customer,
      status: "in_progress",
      channel: "widget",
      current_layer: "human",
      manual_takeover: true,
      processing: true
    )
    ticket.messages.create!(role: "user", content: "Can you update me?")

    assert_no_difference [ "AgentRun.count", "ToolCall.count" ] do
      SupportPipelineJob.perform_now(ticket.id)
    end

    ticket.reload

    assert_equal false, ticket.processing
    assert_equal "in_progress", ticket.status
    assert_equal "human", ticket.current_layer
    assert_equal [ "user" ], ticket.messages.order(:created_at).pluck(:role)
  end
end
