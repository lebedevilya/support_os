require "test_helper"
require Rails.root.join("app/services/llm/client")

class SupportOsFlowTest < ActionDispatch::IntegrationTest
  test "overview page renders support os framing" do
    get root_path

    assert_response :success
    assert_includes response.body, "SupportOS"
    assert_includes response.body, "portfolio-wide support operating system"
    assert_includes response.body, "AI Passport Photo"
    assert_includes response.body, "nodes.garden"
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
      assert_difference "Customer.count", 1 do
        assert_difference "Ticket.count", 1 do
          assert_difference "Message.count", 2 do
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
    assert_equal "resolved", ticket.status
    assert_equal [ "user", "assistant" ], ticket.messages.order(:created_at).pluck(:role)
    assert_equal "I paid but did not receive my file", ticket.messages.order(:created_at).first.content
    assert_equal 2, ticket.agent_runs.count
    assert_equal 1, ticket.tool_calls.count
    assert_select "textarea[name='message[content]'][data-action='keydown->enter-submit#submitOnEnter']"
  end
end
