require "test_helper"

class TicketsInboxTest < ActionDispatch::IntegrationTest
  test "inbox renders with pagination when there are more tickets than one page" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )
    customer = Customer.create!(email: "inbox@example.com")

    # More than the per-page limit (10) so pagy_nav actually renders.
    12.times do |index|
      company.tickets.create!(
        customer: customer,
        status: "new",
        channel: "widget",
        current_layer: "triage"
      )
    end

    get tickets_path

    assert_response :success
    assert_select "nav[aria-label='Pagination']"
    assert_select "a[aria-label='Next page']"

    get tickets_path(page: 2)

    assert_response :success
    assert_select "a[aria-label='Previous page']"
  end

  test "inbox renders when filtered down to a single page" do
    company = Company.create!(
      name: "nodes.garden",
      slug: "nodes-garden",
      description: "Node deployment support",
      support_email: "support@nodes.garden"
    )
    customer = Customer.create!(email: "filter@example.com")
    company.tickets.create!(
      customer: customer,
      status: "escalated",
      channel: "widget",
      current_layer: "triage"
    )

    get tickets_path(company_id: company.id, status: "escalated")

    assert_response :success
  end
end
