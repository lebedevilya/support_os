require "test_helper"
require Rails.root.join("app/services/llm/client")
require "ostruct"

class SupportOsFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "overview page renders support os framing" do
    aipassportphoto = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )
    nodes_garden = Company.create!(
      name: "nodes.garden",
      slug: "nodes-garden",
      description: "Node deployment and provisioning support",
      support_email: "support@nodes.garden"
    )

    get root_path

    assert_response :success
    assert_includes response.body, "Support_OS"
    assert_includes response.body, "portfolio-wide support operating system"
    assert_includes response.body, "AI Passport Photo"
    assert_includes response.body, "nodes.garden"
    assert_select "a[href='#{company_path(aipassportphoto.slug)}']", text: /AI Passport Photo/
    assert_select "a[href='#{company_path(nodes_garden.slug)}']", text: /nodes\.garden/
  end

  test "company landing page renders live site iframe with embedded widget shell" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )

    get company_path(company.slug)

    assert_response :success
    assert_select "iframe[title='#{company.name} site preview'][src='https://www.aipassportphoto.co/']"
    assert_select "[data-controller='widget-shell']"
    assert_select "turbo-frame#support_widget"
    assert_select "input[type='hidden'][name='ticket[company_id]'][value='#{company.id}']"
    assert_select "select[name='ticket[company_id]']", count: 0
    assert_select "button", text: /Chat with support/
    assert_includes response.body, "cursor-pointer rounded-full bg-slate-900"
    assert_select "[data-widget-shell-target='customerEmail']"
    assert_includes response.body, "Example scenarios"
    assert_includes response.body, "Can I make a picture for UK visa?"
    assert_includes response.body, "Where is your office located?"
    assert_select "button[data-scenario-prompt='I did not receive my file, resend the download link']"
    assert_select "button[data-scenario-email='sara@example.com']"
  end

  test "nodes garden company page falls back to the local landing page when live embedding is blocked" do
    company = Company.create!(
      name: "nodes.garden",
      slug: "nodes-garden",
      description: "Node deployment and provisioning support",
      support_email: "support@nodes.garden"
    )

    get company_path(company.slug)

    assert_response :success
    assert_select "iframe", count: 0
    assert_includes response.body, "Launch self-hosted nodes without babysitting infra."
    assert_includes response.body, "Support embedded on the site"
    assert_select "[data-controller='widget-shell']"
    assert_select "turbo-frame#support_widget"
    assert_select "input[type='hidden'][name='ticket[company_id]'][value='#{company.id}']"
    assert_select "button", text: /Chat with support/
  end

  test "widget entry page renders company and customer fields" do
    get new_widget_ticket_path

    assert_response :success
    assert_includes response.body, "Start support conversation"
    assert_includes response.body, %(data-widget-shell-email="")
    assert_includes response.body, %(class="min-h-screen bg-white")
    assert_includes response.body, %(class="mx-auto flex min-h-screen w-full max-w-md flex-col md:w-[36rem] md:max-w-none")
    assert_select "[data-controller='widget-shell']"
    assert_select "[data-widget-shell-target='panel']"
    assert_select "[data-widget-shell-target='openButton']", count: 0
    assert_select "select[name='ticket[company_id]']"
    assert_select "input[name='ticket[email]']"
    assert_select "textarea[name='ticket[content]'][data-action='keydown->enter-submit#submitOnEnter']"
  end

  test "company-scoped widget entry keeps the frame scrollable for long scenario lists" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )

    get new_widget_ticket_path(company_id: company.id)

    assert_response :success
    assert_select "[data-controller='widget-shell']"
    assert_select "[data-widget-shell-target='openButton']", count: 0
    assert_includes response.body, "Example scenarios"
  end

  test "creating a widget ticket stores the first customer message" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )
    BusinessRecord.create!(
      company: company,
      record_type: "photo_request",
      external_id: "APP-1001",
      customer_email: "anna@example.com",
      status: "completed",
      payload: {}
    )

    original_builder = LLM::Client.method(:build_from_env)

    LLM::Client.singleton_class.define_method(:build_from_env) { nil }
    begin
      clear_enqueued_jobs
      assert_difference "Customer.count", 1 do
        assert_difference "Ticket.count", 1 do
          assert_difference "Message.count", 1 do
            assert_enqueued_with(job: SupportPipelineJob) do
              post widget_tickets_path, params: {
                ticket: {
                  company_id: company.id,
                  email: "anna@example.com",
                  content: "I paid but did not receive my file"
                }
              }
            end
          end
        end
      end
    ensure
      LLM::Client.singleton_class.define_method(:build_from_env) do
        original_builder.call
      end
    end

    assert_response :success

    ticket = Ticket.order(:created_at).last
    assert_equal company, ticket.company
    assert_equal "anna@example.com", ticket.customer.email
    assert_equal "widget", ticket.channel
    assert_equal "new", ticket.status
    assert_equal true, ticket.processing
    assert_equal [ "user" ], ticket.messages.order(:created_at).pluck(:role)
    assert_equal "I paid but did not receive my file", ticket.messages.order(:created_at).first.content
    assert_equal 0, ticket.agent_runs.count
    assert_equal 0, ticket.tool_calls.count
    assert_select "turbo-cable-stream-source"
    assert_select "[data-customer-email='anna@example.com']"
    assert_includes response.body, %(data-widget-shell-email="anna@example.com")
    assert_select "[data-role='assistant-loading']"
    assert_select "textarea[name='message[content]'][data-action='keydown->enter-submit#submitOnEnter']", count: 0
    assert_select "form[action='#{close_widget_ticket_path(ticket)}']", count: 0
  end

  test "creating a widget ticket requires a non-blank valid email" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )

    assert_no_difference [ "Customer.count", "Ticket.count", "Message.count" ] do
      post widget_tickets_path, params: {
        ticket: {
          company_id: company.id,
          email: "",
          content: "I paid but did not receive my file"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Email can&#39;t be blank"

    assert_no_difference [ "Customer.count", "Ticket.count", "Message.count" ] do
      post widget_tickets_path, params: {
        ticket: {
          company_id: company.id,
          email: "not-an-email",
          content: "I paid but did not receive my file"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Email is invalid"
  end

  test "rendered follow-up form keeps the widget actions after async reply" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )
    customer = Customer.create!(email: "anna@example.com")
    ticket = company.tickets.create!(
      customer: customer,
      status: "awaiting_customer",
      channel: "widget",
      current_layer: "specialist",
      processing: false
    )
    ticket.messages.create!(role: "user", content: "I paid but did not receive my file")
    ticket.messages.create!(role: "assistant", content: "I found your request.")

    html = ApplicationController.render(
      partial: "widget/tickets/chat",
      locals: { ticket: ticket }
    )

    assert_includes html, %(data-widget-shell-email="anna@example.com")
    assert_includes html, %(action="#{widget_ticket_messages_path(ticket)}")
    assert_includes html, %(action="#{close_widget_ticket_path(ticket)}")
    assert_includes html, %(data-action="keydown-&gt;enter-submit#submitOnEnter")
    assert_includes html, %(aria-label="Send message")
    assert_includes html, "Close the ticket"
    assert_includes html, "cursor-pointer rounded-full border border-slate-300"
    assert_not_includes html, "Example scenarios"
    assert_not_includes html, "What is the status of my photo request?"
  end

  test "rendered chat keeps the transcript in a dedicated scroll region" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )
    customer = Customer.create!(email: "anna@example.com")
    ticket = company.tickets.create!(
      customer: customer,
      status: "awaiting_customer",
      channel: "widget",
      current_layer: "specialist",
      processing: false
    )
    8.times do |index|
      ticket.messages.create!(role: index.even? ? "user" : "assistant", content: "Message #{index}")
    end

    html = ApplicationController.render(
      partial: "widget/tickets/chat",
      locals: { ticket: ticket }
    )

    assert_includes html, %(class="flex h-full min-h-0 flex-col")
    assert_includes html, %(class="min-h-0 flex-1 space-y-3 overflow-y-auto pr-1")
  end

  test "rendered escalated chat shows a human specialist waiting state for customers" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )
    customer = Customer.create!(email: "anna@example.com")
    ticket = company.tickets.create!(
      customer: customer,
      status: "escalated",
      channel: "widget",
      current_layer: "human",
      manual_takeover: true,
      processing: false
    )
    ticket.messages.create!(role: "user", content: "My photo was rejected by the embassy and I want a refund right now")
    ticket.messages.create!(role: "human", content: "Escalated for human review because the customer reports an embassy rejection dispute.")

    html = ApplicationController.render(
      partial: "widget/tickets/chat",
      locals: { ticket: ticket }
    )

    assert_includes html, "A human specialist is now reviewing your ticket"
    assert_includes html, "You can leave this page safely"
    assert_not_includes html, "Example scenarios"
    assert_operator html.index("Escalated for human review because the customer reports an embassy rejection dispute."),
                    :<,
                    html.index("Waiting On Human Specialist")
  end

  test "rendered chat wires transcript auto-scroll behavior" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )
    customer = Customer.create!(email: "anna@example.com")
    ticket = company.tickets.create!(
      customer: customer,
      status: "awaiting_customer",
      channel: "widget",
      current_layer: "specialist",
      processing: false
    )
    ticket.messages.create!(role: "user", content: "First")
    ticket.messages.create!(role: "assistant", content: "Second")

    html = ApplicationController.render(
      partial: "widget/tickets/chat",
      locals: { ticket: ticket }
    )

    assert_includes html, %(data-controller="auto-scroll")
    assert_includes html, %(data-auto-scroll-target="viewport")
  end

  test "customer can close the ticket from the widget" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )
    customer = Customer.create!(email: "anna@example.com")
    ticket = company.tickets.create!(
      customer: customer,
      status: "awaiting_customer",
      channel: "widget",
      current_layer: "specialist"
    )
    ticket.messages.create!(role: "user", content: "I paid but did not receive my file")
    ticket.messages.create!(role: "assistant", content: "I found your request. Source: https://www.aipassportphoto.co/contact")

    patch close_widget_ticket_path(ticket), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_equal "resolved", ticket.reload.status
    assert_includes response.body, %(<turbo-stream action="replace" target="#{ActionView::RecordIdentifier.dom_id(ticket, :chat)}">)
    assert_includes response.body, "This conversation is closed."
    assert_includes response.body, "Start a new conversation"
    assert_includes response.body, new_widget_ticket_path(company_id: company.id)
    assert_not_includes response.body, widget_ticket_messages_path(ticket)
    assert_includes response.body, %(href="https://www.aipassportphoto.co/contact")
  end

  test "follow-up returns a turbo stream with the new user message and loading state immediately" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )
    customer = Customer.create!(email: "anna@example.com")
    ticket = company.tickets.create!(
      customer: customer,
      status: "awaiting_customer",
      channel: "widget",
      current_layer: "specialist",
      processing: false
    )
    ticket.messages.create!(role: "user", content: "I paid but did not receive my file")
    ticket.messages.create!(role: "assistant", content: "I found your request.")

    clear_enqueued_jobs

    assert_enqueued_with(job: SupportPipelineJob) do
      post widget_ticket_messages_path(ticket),
           params: { message: { content: "Can you check the status again?" } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_equal true, ticket.reload.processing
    assert_includes response.body, %(<turbo-stream action="replace" target="#{ActionView::RecordIdentifier.dom_id(ticket, :chat)}">)
    assert_includes response.body, "Can you check the status again?"
    assert_includes response.body, "Assistant is typing"
    assert_includes response.body, "Thinking"
  end

  test "inbox shows category and confidence for support tickets" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )
    customer = Customer.create!(email: "anna@example.com")
    ticket = company.tickets.create!(
      customer: customer,
      status: "awaiting_customer",
      category: "delivery",
      priority: "normal",
      channel: "widget",
      current_layer: "specialist",
      last_confidence: 0.87
    )

    get tickets_path

    assert_response :success
    assert_select "td", text: "delivery"
    assert_select "td", text: "87%"
    assert_select "tr[onclick=\"window.location='#{ticket_path(ticket)}'\"]"
  end

  test "escalated tickets sort to the top and are visually marked as urgent" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )
    customer = Customer.create!(email: "anna@example.com")
    normal_ticket = company.tickets.create!(
      customer: customer,
      status: "awaiting_customer",
      category: "policy",
      priority: "normal",
      channel: "widget",
      current_layer: "specialist",
      last_confidence: 0.91,
      updated_at: 2.hours.ago
    )
    escalated_ticket = company.tickets.create!(
      customer: customer,
      status: "escalated",
      category: "delivery",
      priority: "high",
      channel: "widget",
      current_layer: "human",
      last_confidence: 0.54,
      updated_at: 3.hours.ago
    )

    get tickets_path

    assert_response :success
    assert_match(/##{escalated_ticket.id}.*##{normal_ticket.id}/m, response.body)
    assert_select "tr.bg-rose-50"
    assert_select "span", text: "Needs support"
  end

  test "ticket detail and trace pages expose operational context" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )
    customer = Customer.create!(email: "anna@example.com")
    ticket = company.tickets.create!(
      customer: customer,
      status: "escalated",
      category: "delivery",
      priority: "high",
      channel: "widget",
      current_layer: "human",
      manual_takeover: true,
      last_confidence: 0.64,
      summary: "Delivery request could not be safely completed automatically.",
      escalation_reason: "Automation confidence 0.64 was below the required threshold of 0.7.",
      handoff_note: "Escalated for human review because specialist confidence was below the automation threshold."
    )
    ticket.tag_list = [ "delivery", "human-review" ]
    ticket.save!
    ticket.messages.create!(role: "user", content: "I paid but did not receive my file")
    ticket.messages.create!(role: "human", content: "Escalated for human review because specialist confidence was below the automation threshold.")
    agent_run = ticket.agent_runs.create!(
      agent_name: "SpecialistAgent",
      status: "escalated",
      decision: "escalate",
      confidence: 0.64,
      input_snapshot: "I paid but did not receive my file",
      output_snapshot: {
        source: "llm",
        status: "escalated",
        category: "delivery",
        priority: "high",
        route: "escalate",
        current_layer: "human",
        confidence: 0.64,
        decision: "escalate",
        escalation_reason: "Automation confidence 0.64 was below the required threshold of 0.7.",
        handoff_note: "Escalated for human review because specialist confidence was below the automation threshold."
      }.to_json,
      reasoning_summary: "Escalated by pipeline confidence guardrail."
    )
    ticket.tool_calls.create!(
      agent_run: agent_run,
      tool_name: "lookup_photo_request",
      status: "success",
      input_payload: { email: customer.email }.to_json,
      output_payload: { external_id: "APP-1001", status: "completed" }.to_json
    )
    ticket.tool_calls.create!(
      agent_run: agent_run,
      tool_name: "resend_download_link",
      status: "success",
      input_payload: { external_id: "APP-1001" }.to_json,
      output_payload: { external_id: "APP-1001", download_url: "https://example.test/download/APP-1001", completed: true }.to_json
    )

    get ticket_path(ticket)

    assert_response :success
    assert_includes response.body, "Back to tickets"
    assert_includes response.body, "Delivery request could not be safely completed automatically."
    assert_includes response.body, "Automation confidence 0.64 was below the required threshold of 0.7."
    assert_includes response.body, "Human-owned ticket"
    assert_includes response.body, "New customer replies now stay with support"
    assert_includes response.body, "delivery"
    assert_includes response.body, "human-review"
    assert_includes response.body, "lookup_photo_request"
    assert_includes response.body, "resend_download_link"

    get ticket_trace_path(ticket)

    assert_response :success
    assert_includes response.body, "Back to ticket"
    assert_includes response.body, "Manual takeover is active"
    assert_includes response.body, "Customer message"
    assert_includes response.body, "Specialist step"
    assert_includes response.body, "Lookup tool"
    assert_includes response.body, "Action completed"
    assert_includes response.body, "Escalated by pipeline confidence guardrail."
    assert_includes response.body, "external_id"
    assert_includes response.body, "APP-1001"
    assert_includes response.body, "anna@example.com"
  end

  test "human support can reply from the ticket page" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )
    customer = Customer.create!(email: "anna@example.com")
    ticket = company.tickets.create!(
      customer: customer,
      status: "escalated",
      category: "delivery",
      priority: "high",
      channel: "widget",
      current_layer: "human",
      escalation_reason: "Needs human review.",
      handoff_note: "Escalated to support."
    )
    ticket.messages.create!(role: "user", content: "I paid but did not receive my file")

    assert_difference "Message.count", 1 do
      post reply_ticket_path(ticket), params: {
        message: { content: "I found your order and I am checking the delivery details now." }
      }
    end

    assert_redirected_to ticket_path(ticket, anchor: "support-reply")

    ticket.reload
    assert_equal "awaiting_customer", ticket.status
    assert_equal "human", ticket.current_layer
    assert_equal true, ticket.manual_takeover
    assert_nil ticket.escalation_reason
    assert_nil ticket.handoff_note
    assert_equal "human", ticket.messages.order(:created_at).last.role
    assert_includes ticket.messages.order(:created_at).last.content, "checking the delivery details"

    follow_redirect!
    assert_response :success
    assert_includes response.body, "Reply as support"
    assert_includes response.body, "Waiting on customer"
    assert_includes response.body, "checking the delivery details"
  end

  test "follow-up on a manually owned ticket does not re-enter the agent pipeline" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )
    customer = Customer.create!(email: "anna@example.com")
    ticket = company.tickets.create!(
      customer: customer,
      status: "awaiting_customer",
      category: "delivery",
      priority: "high",
      channel: "widget",
      current_layer: "human",
      manual_takeover: true,
      processing: false
    )
    ticket.messages.create!(role: "user", content: "I paid but did not receive my file")
    ticket.messages.create!(role: "human", content: "I found your order and I am checking the delivery details now.")

    assert_no_enqueued_jobs only: SupportPipelineJob do
      post widget_ticket_messages_path(ticket),
           params: { message: { content: "Thanks, can you update me tomorrow?" } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type

    ticket.reload
    assert_equal false, ticket.processing
    assert_equal true, ticket.manual_takeover
    assert_equal "human", ticket.current_layer
    assert_equal "in_progress", ticket.status
    assert_equal [ "user", "human", "user" ], ticket.messages.order(:created_at).pluck(:role)
    assert_includes response.body, "Thanks, can you update me tomorrow?"
    assert_not_includes response.body, "Loading..."

    get ticket_path(ticket)

    assert_response :success
    assert_includes response.body, "Waiting on support"
  end

  test "widget shows manual handoff button when automation offers human help" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )
    customer = Customer.create!(email: "anna@example.com")
    ticket = company.tickets.create!(
      customer: customer,
      status: "awaiting_customer",
      category: "refund",
      priority: "high",
      channel: "widget",
      current_layer: "triage",
      processing: false,
      human_handoff_available: true,
      summary: "Refund dispute needs a human specialist.",
      escalation_reason: "Embassy rejection disputes require human review.",
      handoff_note: "A human specialist can take over this ticket if the customer asks."
    )
    ticket.messages.create!(role: "user", content: "My photo was rejected by the embassy.")
    ticket.messages.create!(role: "assistant", content: "This case needs human review. Use the button below if you want a human specialist.")

    get ticket_path(ticket)

    assert_response :success
    assert_includes response.body, "Refund dispute needs a human specialist."

    html = ApplicationController.render(
      partial: "widget/tickets/chat",
      locals: { ticket: ticket }
    )

    assert_includes html, "Chat to human"
    assert_not_includes html, "Waiting On Human Specialist"
  end

  test "clicking the widget handoff button makes the ticket human owned" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )
    customer = Customer.create!(email: "anna@example.com")
    ticket = company.tickets.create!(
      customer: customer,
      status: "awaiting_customer",
      category: "refund",
      priority: "high",
      channel: "widget",
      current_layer: "triage",
      processing: false,
      human_handoff_available: true,
      summary: "Refund dispute needs a human specialist.",
      escalation_reason: "Embassy rejection disputes require human review.",
      handoff_note: "A human specialist can take over this ticket if the customer asks."
    )
    ticket.messages.create!(role: "user", content: "My photo was rejected by the embassy.")
    ticket.messages.create!(role: "assistant", content: "This case needs human review. Use the button below if you want a human specialist.")

    patch handoff_widget_ticket_path(ticket), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success

    ticket.reload
    assert_equal true, ticket.manual_takeover
    assert_equal false, ticket.human_handoff_available
    assert_equal "human", ticket.current_layer
    assert_equal "in_progress", ticket.status
    assert_includes response.body, "Waiting On Human Specialist"
  end

  test "tickets index supports filtering, counts, and pagination" do
    aipassportphoto = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )
    nodes_garden = Company.create!(
      name: "nodes.garden",
      slug: "nodes-garden",
      description: "Node deployment support",
      support_email: "support@nodes.garden"
    )
    customer = Customer.create!(email: "anna@example.com")

    first_ticket = aipassportphoto.tickets.create!(
      customer: customer,
      status: "awaiting_customer",
      category: "policy",
      priority: "normal",
      channel: "widget",
      current_layer: "specialist",
      last_confidence: 0.91
    )
    first_ticket.tag_list = [ "canada", "policy" ]
    first_ticket.save!

    second_ticket = aipassportphoto.tickets.create!(
      customer: customer,
      status: "escalated",
      category: "delivery",
      priority: "high",
      channel: "widget",
      current_layer: "human",
      last_confidence: 0.51
    )
    second_ticket.tag_list = [ "delivery", "refund-risk" ]
    second_ticket.save!

    third_ticket = nodes_garden.tickets.create!(
      customer: customer,
      status: "awaiting_customer",
      category: "technical",
      priority: "normal",
      channel: "widget",
      current_layer: "specialist",
      last_confidence: 0.88
    )
    third_ticket.tag_list = [ "provisioning", "node" ]
    third_ticket.save!

    get tickets_path, params: { company_id: aipassportphoto.id, status: "awaiting_customer", tag: "canada" }

    assert_response :success
    assert_includes response.body, "Total tickets"
    assert_includes response.body, "AI Passport Photo"
    assert_includes response.body, "nodes.garden"
    assert_includes response.body, "awaiting_customer"
    assert_includes response.body, "escalated"
    assert_includes response.body, "canada"
    assert_includes response.body, "delivery"
    assert_includes response.body, "Page 1 of 1"
    assert_includes response.body, "##{first_ticket.id}"
    assert_not_includes response.body, "##{second_ticket.id}"
    assert_not_includes response.body, "##{third_ticket.id}"
  end

  test "motor admin is protected by basic auth backed by rails credentials" do
    with_stubbed_credentials(nil, "motor-user", "motor-pass") do
      get "/admin"
      assert_response :unauthorized

      auth = ActionController::HttpAuthentication::Basic.encode_credentials("motor-user", "motor-pass")
      get "/admin", headers: { "Authorization" => auth }

      assert_not_equal 401, response.status
    end
  end

  private

  def with_stubbed_credentials(open_ai_key, motor_username = nil, motor_password = nil)
    application = Rails.application
    original_method = application.method(:credentials)

    application.singleton_class.define_method(:credentials) do
      OpenStruct.new(
        open_ai: OpenStruct.new(api_key: open_ai_key),
        motor_admin: OpenStruct.new(username: motor_username, password: motor_password)
      )
    end

    yield
  ensure
    application.singleton_class.define_method(:credentials) do
      original_method.call
    end
  end
end
