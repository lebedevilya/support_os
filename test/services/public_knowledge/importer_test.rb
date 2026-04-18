require "test_helper"

class PublicKnowledge::ImporterTest < ActiveSupport::TestCase
  test "imports visible text into a source and generates chunks without storing html" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )

    source = Knowledge::Source.create!(
      company: company,
      url: "https://www.aipassportphoto.co/",
      source_kind: "website_page",
      status: "pending"
    )

    html = <<~HTML
      <html>
        <body>
          <main>
            <h1>AI Passport Photo</h1>
            <p>Under 60 seconds. Upload your photo, our AI processes it instantly.</p>
            <p>Download or print your compliant passport photo right away.</p>
          </main>
        </body>
      </html>
    HTML

    PublicKnowledge::Importer.new(source: source, html: html).call

    source.reload

    assert_equal "imported", source.status
    assert_includes source.extracted_text, "Under 60 seconds"
    refute_includes source.extracted_text, "<h1>"
    assert source.imported_at.present?
    assert source.chunks.any?
    assert_includes source.chunks.order(:position).first.content, "Under 60 seconds"
  end
end
