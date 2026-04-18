require "test_helper"

class PublicKnowledge::RetrieverTest < ActiveSupport::TestCase
  test "returns company-scoped chunks for faq-style questions" do
    passport_company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )
    nodes_company = Company.create!(
      name: "nodes.garden",
      slug: "nodes-garden",
      description: "Node deployment support",
      support_email: "support@nodes.garden"
    )

    source = Knowledge::Source.create!(
      company: passport_company,
      url: "https://www.aipassportphoto.co/",
      title: "Homepage",
      source_kind: "website_page",
      status: "imported",
      extracted_text: "Under 60 seconds. Upload your photo, our AI processes it instantly."
    )
    source.chunks.create!(
      company: passport_company,
      content: "Under 60 seconds. Upload your photo, our AI processes it instantly.",
      position: 0,
      token_estimate: 12
    )

    other_source = Knowledge::Source.create!(
      company: nodes_company,
      url: "https://nodes.garden/",
      title: "Homepage",
      source_kind: "website_page",
      status: "imported",
      extracted_text: "Deploy nodes with fast provisioning."
    )
    other_source.chunks.create!(
      company: nodes_company,
      content: "Deploy nodes with fast provisioning.",
      position: 0,
      token_estimate: 6
    )

    results = PublicKnowledge::Retriever.new(
      company: passport_company,
      query: "How long does it take?"
    ).call

    assert_equal 1, results.size
    assert_includes results.first.content, "Under 60 seconds"
  end
end
