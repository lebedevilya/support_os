require "test_helper"

class PublicKnowledge::LinkDiscovererTest < ActiveSupport::TestCase
  test "returns same-domain page links from the body" do
    html = <<~HTML
      <html>
        <head>
          <link rel="alternate" href="https://www.aipassportphoto.co/de" />
        </head>
        <body>
          <main>
            <a href="/privacy">Privacy</a>
            <a href="https://www.aipassportphoto.co/terms">Terms</a>
            <a href="/guarantee#refunds">Guarantee</a>
            <a href="mailto:support@aipassportphoto.co">Email</a>
            <a href="https://example.com/offsite">Offsite</a>
          </main>
        </body>
      </html>
    HTML

    links = PublicKnowledge::LinkDiscoverer.new(root_url: "https://www.aipassportphoto.co/", html: html).call

    assert_equal [
      "https://www.aipassportphoto.co/guarantee",
      "https://www.aipassportphoto.co/privacy",
      "https://www.aipassportphoto.co/terms"
    ], links
  end
end
