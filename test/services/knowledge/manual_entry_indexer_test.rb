require "test_helper"

class Knowledge::ManualEntryIndexerTest < ActiveSupport::TestCase
  test "creates chunks for an active manual entry" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )

    manual_entry = Knowledge::ManualEntry.create!(
      company: company,
      title: "Turnaround time",
      content: "Most passport photo requests are completed in under 60 seconds.",
      status: "draft"
    )

    assert_equal 0, manual_entry.chunks.count

    manual_entry.update!(status: "active")

    assert_equal 1, manual_entry.reload.chunks.count
    assert_includes manual_entry.chunks.first.content, "under 60 seconds"
  end

  test "removes chunks when a manual entry is no longer active" do
    company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )

    manual_entry = Knowledge::ManualEntry.create!(
      company: company,
      title: "Support contact",
      content: "Customers can email help@aipassportphoto.co for support.",
      status: "active"
    )

    assert_equal 1, manual_entry.chunks.count

    manual_entry.update!(status: "archived")

    assert_equal 0, manual_entry.reload.chunks.count
  end
end
