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

  test "ignores script and hidden content when extracting visible text" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )

    source = Knowledge::Source.create!(
      company: company,
      url: "https://www.aipassportphoto.co/contact",
      source_kind: "website_page",
      status: "pending"
    )

    html = <<~HTML
      <html>
        <body>
          <main>
            <h1>Contact Us</h1>
            <p>Email support@aipassportphoto.co</p>
            <div hidden>This hidden text should not be imported.</div>
          </main>
          <script>
            window.__NEXT_DATA__ = { hydration: "noise that should not appear" }
          </script>
        </body>
      </html>
    HTML

    PublicKnowledge::Importer.new(source: source, html: html).call

    source.reload

    assert_includes source.extracted_text, "Contact Us"
    assert_includes source.extracted_text, "support@aipassportphoto.co"
    refute_includes source.extracted_text, "hydration"
    refute_includes source.extracted_text, "hidden text"
  end

  test "keeps streamed nextjs content even when wrapped in hidden containers" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )

    source = Knowledge::Source.create!(
      company: company,
      url: "https://www.aipassportphoto.co/guarantee",
      source_kind: "website_page",
      status: "pending"
    )

    html = <<~HTML
      <html>
        <body>
          <div hidden id="S:0">
            <main>
              <h1>Money-Back Guarantee</h1>
              <p>If your photo is rejected by an official agency, we will refund you.</p>
            </main>
          </div>
          <div hidden>This hidden text should not be imported.</div>
        </body>
      </html>
    HTML

    PublicKnowledge::Importer.new(source: source, html: html).call

    source.reload

    assert_includes source.extracted_text, "Money-Back Guarantee"
    assert_includes source.extracted_text, "official agency"
    refute_includes source.extracted_text, "hidden text"
  end
end
