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

  test "company landing page renders branded page with embedded widget shell" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )

    get company_path(company.slug)

    assert_response :success
    assert_includes response.body, "AI Passport Photo"
    assert_select "[data-controller='widget-shell']"
    assert_select "turbo-frame#support_widget"
    assert_select "input[type='hidden'][name='ticket[company_id]'][value='#{company.id}']"
    assert_select "select[name='ticket[company_id]']", count: 0
    assert_select "button", text: /Chat with support/
  end

  test "widget entry page renders company and customer fields" do
    get new_widget_ticket_path

    assert_response :success
    assert_includes response.body, "Start support conversation"
    assert_select "select[name='ticket[company_id]']"
    assert_select "input[name='ticket[email]']"
    assert_select "textarea[name='ticket[content]'][data-action='keydown->enter-submit#submitOnEnter']"
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
    assert_select "[data-role='assistant-loading']"
    assert_select "textarea[name='message[content]'][data-action='keydown->enter-submit#submitOnEnter']", count: 0
    assert_select "form[action='#{close_widget_ticket_path(ticket)}']", count: 0
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

    assert_includes html, %(action="#{widget_ticket_messages_path(ticket)}")
    assert_includes html, %(action="#{close_widget_ticket_path(ticket)}")
    assert_includes html, %(data-action="keydown-&gt;enter-submit#submitOnEnter")
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
    assert_includes response.body, "Loading..."
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
