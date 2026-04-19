require "test_helper"

class PublicKnowledge::SiteImporterTest < ActiveSupport::TestCase
  test "imports the root page and discovered same-domain pages" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )

    responses = {
      "https://www.aipassportphoto.co/" => <<~HTML,
        <html>
          <body>
            <main>
              <h1>Homepage</h1>
              <p>Passport photos in seconds.</p>
              <a href="/privacy">Privacy</a>
              <a href="/contact">Contact</a>
            </main>
          </body>
        </html>
      HTML
      "https://www.aipassportphoto.co/privacy" => <<~HTML,
        <html><body><main><h1>Privacy</h1><p>Uploaded photos are deleted after 30 days.</p></main></body></html>
      HTML
      "https://www.aipassportphoto.co/contact" => <<~HTML
        <html><body><main><h1>Contact</h1><p>Email support@aipassportphoto.co.</p></main></body></html>
      HTML
    }

    fetcher = ->(url) { responses.fetch(url) }

    PublicKnowledge::SiteImporter.new(
      company: company,
      root_url: "https://www.aipassportphoto.co/",
      fetcher: fetcher
    ).call

    sources = company.knowledge_sources.order(:url)

    assert_equal 3, sources.count
    assert_equal [
      "https://www.aipassportphoto.co/",
      "https://www.aipassportphoto.co/contact",
      "https://www.aipassportphoto.co/privacy"
    ], sources.pluck(:url)
    assert sources.all? { |source| source.status == "imported" }
    assert sources.all? { |source| source.chunks.any? }
  end
end
