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

  test "prefers curated manual knowledge over noisy imported pages" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )

    noisy_source = Knowledge::Source.create!(
      company: company,
      url: "https://www.aipassportphoto.co/terms",
      title: "Terms of Service Last updated",
      source_kind: "website_page",
      status: "imported",
      extracted_text: "Canada users agree to the service terms. Passport services are subject to the general website conditions."
    )
    noisy_source.chunks.create!(
      company: company,
      content: "Canada users agree to the service terms. Passport services are subject to the general website conditions.",
      position: 0,
      token_estimate: 15
    )

    manual_entry = Knowledge::ManualEntry.create!(
      company: company,
      title: "Canada passport photos",
      content: "AI Passport Photo supports Canada passport photos and prepares them in the required 50 x 70 mm format.",
      status: "active"
    )

    results = PublicKnowledge::Retriever.new(
      company: company,
      query: "Can I make Canada passport picture?"
    ).matches

    assert_equal manual_entry, results.first.chunk.manual_entry
    assert_includes results.first.chunk.content, "50 x 70 mm"
  end
end
