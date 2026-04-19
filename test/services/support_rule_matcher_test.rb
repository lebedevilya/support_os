require "test_helper"

class SupportRuleMatcherTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(
      name: "AI Passport Photo",
      slug: "aipassportphoto",
      description: "Passport photo support",
      support_email: "help@aipassportphoto.co"
    )
  end

  test "prefers company-specific rules over global rules" do
    global_rule = SupportRule.create!(
      name: "Global embassy refund escalation",
      active: true,
      priority: 20,
      match_type: "all_terms",
      terms: "embassy\nrefund",
      route: "escalate",
      category: "refund",
      priority_level: "high",
      confidence: 0.92,
      reasoning_summary: "Global refund disputes require human review.",
      escalation_reason: "Global rule matched.",
      handoff_note: "Escalated by global rule."
    )

    company_rule = SupportRule.create!(
      company: @company,
      name: "Company embassy refund escalation",
      active: true,
      priority: 10,
      match_type: "all_terms",
      terms: "embassy\nrefund",
      route: "escalate",
      category: "refund",
      priority_level: "high",
      confidence: 0.97,
      reasoning_summary: "Company-specific refund disputes require human review.",
      escalation_reason: "Company rule matched.",
      handoff_note: "Escalated by company rule."
    )

    result = SupportRuleMatcher.new(company: @company, content: "My photo was rejected by the embassy and I want a refund").call

    assert_equal company_rule, result.rule
    assert_not_equal global_rule, result.rule
    assert_equal "Company rule matched.", result.attributes.fetch(:escalation_reason)
  end

  test "supports any-terms matching" do
    rule = SupportRule.create!(
      company: @company,
      name: "Fraud or chargeback escalation",
      active: true,
      priority: 10,
      match_type: "any_terms",
      terms: "fraud\nchargeback",
      route: "escalate",
      category: "billing",
      priority_level: "high",
      confidence: 0.95,
      reasoning_summary: "Sensitive billing issues require human review.",
      escalation_reason: "Sensitive billing rule matched.",
      handoff_note: "Escalated by billing rule."
    )

    result = SupportRuleMatcher.new(company: @company, content: "I want a chargeback").call

    assert_equal rule, result.rule
  end

  test "knowledge blocker rules are excluded from normal routing matches" do
    SupportRule.create!(
      company: @company,
      name: "Operational requests should not use public knowledge",
      active: true,
      priority: 10,
      match_type: "any_terms",
      terms: "payment\nrefund",
      route: "specialist",
      category: "other",
      priority_level: "normal",
      confidence: 0.9,
      reasoning_summary: "Operational requests should not be answered from public knowledge.",
      blocks_public_knowledge: true
    )

    result = SupportRuleMatcher.new(company: @company, content: "I need a refund for my payment").call

    assert_nil result
  end

  test "knowledge blocker rules can be matched in blocker mode" do
    rule = SupportRule.create!(
      company: @company,
      name: "Operational requests should not use public knowledge",
      active: true,
      priority: 10,
      match_type: "any_terms",
      terms: "payment\nrefund",
      route: "specialist",
      category: "other",
      priority_level: "normal",
      confidence: 0.9,
      reasoning_summary: "Operational requests should not be answered from public knowledge.",
      blocks_public_knowledge: true
    )

    result = SupportRuleMatcher.new(company: @company, content: "I need a refund for my payment", blocker_only: true).call

    assert_equal rule, result.rule
  end
end
