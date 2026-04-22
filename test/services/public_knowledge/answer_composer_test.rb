require "test_helper"

class PublicKnowledge::AnswerComposerTest < ActiveSupport::TestCase
  test "extracts the most relevant sentence instead of dumping the full chunk" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )

    source = Knowledge::Source.create!(
      company: company,
      url: "https://www.aipassportphoto.co/",
      title: "Homepage",
      source_kind: "website_page",
      status: "imported",
      extracted_text: "Upload your photo from any device. Most passport photo requests are completed in under 60 seconds. Download or print the final image right away."
    )
    chunk = source.chunks.create!(
      company: company,
      content: "Upload your photo from any device. Most passport photo requests are completed in under 60 seconds. Download or print the final image right away.",
      position: 0,
      token_estimate: 22
    )

    answer = PublicKnowledge::AnswerComposer.new(
      question: "How long does it take to get a passport photo?",
      chunk: chunk
    ).call

    assert_includes answer, "under 60 seconds"
    refute_includes answer, "Upload your photo from any device"
    refute_includes answer, "Download or print the final image right away"
  end

  test "keeps a direct yes-no opening for country support questions" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto-yes-no",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )

    manual_entry = Knowledge::ManualEntry.create!(
      company: company,
      title: "Canada passport photos",
      content: "AI Passport Photo supports Canada passport photos and prepares them in the required 50 x 70 mm format.",
      status: "active"
    )
    chunk = manual_entry.chunks.first

    answer = PublicKnowledge::AnswerComposer.new(
      question: "Can I make Canada passport picture?",
      chunk: chunk
    ).call

    assert_match(/\AYes, you can\./, answer)
    assert_includes answer, "Canada passport photos"
  end
end
