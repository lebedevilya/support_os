class SupportRuleMatcher
  Result = Struct.new(:rule, :attributes, keyword_init: true)

  def initialize(company:, content:, blocker_only: false)
    @company = company
    @content = content.to_s.downcase
    @blocker_only = blocker_only
  end

  def call
    matching_rule = scoped_rules.find { |rule| matches?(rule) }
    return unless matching_rule

    Result.new(rule: matching_rule, attributes: build_attributes(matching_rule))
  end

  private

  def scoped_rules
    scope = @blocker_only ? SupportRule.knowledge_blockers : SupportRule.routing_rules

    company_rules = scope.where(company: @company).active_first.to_a
    global_rules = scope.where(company_id: nil).active_first.to_a
    company_rules + global_rules
  end

  def matches?(rule)
    terms = rule.term_list.map(&:downcase)
    return false if terms.empty?

    case rule.match_type
    when "all_terms"
      terms.all? { |term| @content.include?(term) }
    when "any_terms"
      terms.any? { |term| @content.include?(term) }
    else
      false
    end
  end

  def build_attributes(rule)
    handoff_offer = rule.route == "escalate"

    {
      source: "support_rule",
      matched_rule_id: rule.id,
      matched_rule_name: rule.name,
      status: handoff_offer ? "awaiting_customer" : "in_progress",
      category: rule.category,
      priority: rule.priority_level,
      route: handoff_offer ? "offer_human_handoff" : rule.route,
      current_layer: handoff_offer ? "triage" : "specialist",
      confidence: rule.confidence.to_f,
      decision: handoff_offer ? "offer_human_handoff" : "triage",
      escalation_reason: rule.escalation_reason,
      handoff_note: rule.handoff_note,
      summary: rule.reasoning_summary,
      reply: handoff_offer ? "This case needs human review. Use the button below if you want a human specialist to take over." : nil,
      human_handoff_available: handoff_offer,
      reasoning_summary: rule.reasoning_summary,
      tags: [ rule.category, rule.name ]
    }
  end
end
