require "test_helper"
require "ostruct"

class WidgetRegressionApiTest < ActionDispatch::IntegrationTest
  test "requires a bearer token" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )

    post "/widget/test_api/tickets",
         params: {
           company_slug: company.slug,
           email: "anna@example.com",
           content: "Hi"
         },
         as: :json

    assert_response :unauthorized
  end

  test "creates a regression ticket and enqueues the pipeline job" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )

    with_stubbed_credentials(nil, regression_api_token: "secret-token") do
      clear_enqueued_jobs

      assert_enqueued_with(job: SupportPipelineJob) do
        post "/widget/test_api/tickets",
             params: {
               company_slug: company.slug,
               email: "anna@example.com",
               content: "Hi"
             },
             headers: bearer_headers("secret-token"),
             as: :json
      end
    end

    assert_response :created
    body = JSON.parse(response.body)
    ticket = Ticket.find(body.fetch("ticket").fetch("id"))

    assert_equal company, ticket.company
    assert_equal "anna@example.com", ticket.customer.email
    assert_equal "widget", ticket.channel
    assert_equal true, ticket.processing
    assert_equal "Hi", ticket.messages.order(:created_at).first.content
    assert_equal "new", body.fetch("ticket").fetch("status")
    assert_equal "Hi", body.fetch("ticket").fetch("messages").first.fetch("content")
  end

  test "shows ticket state and latest assistant message" do
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
      current_layer: "triage",
      processing: false
    )
    ticket.messages.create!(role: "user", content: "Hi")
    ticket.messages.create!(role: "assistant", content: "Hello! What do you need help with today?")

    with_stubbed_credentials(nil, regression_api_token: "secret-token") do
      get "/widget/test_api/tickets/#{ticket.id}",
          headers: bearer_headers("secret-token"),
          as: :json
    end

    assert_response :success
    body = JSON.parse(response.body)

    assert_equal ticket.id, body.fetch("ticket").fetch("id")
    assert_equal false, body.fetch("ticket").fetch("processing")
    assert_equal "Hello! What do you need help with today?", body.fetch("ticket").fetch("latest_assistant_message")
    assert_equal 2, body.fetch("ticket").fetch("messages").size
  end

  test "posts a follow-up message and enqueues the pipeline job" do
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
      current_layer: "triage",
      processing: false
    )
    ticket.messages.create!(role: "user", content: "Hi")
    ticket.messages.create!(role: "assistant", content: "Hello! What do you need help with today?")

    with_stubbed_credentials(nil, regression_api_token: "secret-token") do
      clear_enqueued_jobs

      assert_enqueued_with(job: SupportPipelineJob) do
        post "/widget/test_api/tickets/#{ticket.id}/messages",
             params: { content: "Do you support Germany passport photos?" },
             headers: bearer_headers("secret-token"),
             as: :json
      end
    end

    assert_response :created
    body = JSON.parse(response.body)

    assert_equal true, ticket.reload.processing
    assert_equal "Do you support Germany passport photos?", ticket.messages.order(:created_at).last.content
    assert_equal "Do you support Germany passport photos?", body.fetch("ticket").fetch("latest_user_message")
  end

  test "closes a ticket through the regression api" do
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
      current_layer: "triage",
      processing: false
    )

    with_stubbed_credentials(nil, regression_api_token: "secret-token") do
      post "/widget/test_api/tickets/#{ticket.id}/close",
           headers: bearer_headers("secret-token"),
           as: :json
    end

    assert_response :success
    assert_equal "resolved", ticket.reload.status
    assert_equal false, ticket.human_handoff_available
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def with_stubbed_credentials(open_ai_key, motor_username = nil, motor_password = nil, regression_api_token: nil)
    application = Rails.application
    original_method = application.method(:credentials)

    application.singleton_class.define_method(:credentials) do
      OpenStruct.new(
        open_ai: OpenStruct.new(api_key: open_ai_key),
        motor_admin: OpenStruct.new(username: motor_username, password: motor_password),
        regression_api: OpenStruct.new(token: regression_api_token)
      )
    end

    yield
  ensure
    application.singleton_class.define_method(:credentials) do
      original_method.call
    end
  end
end
