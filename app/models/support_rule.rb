class SupportRule < ApplicationRecord
  belongs_to :company, optional: true

  enum :match_type, {
    all_terms: "all_terms",
    any_terms: "any_terms"
  }

  enum :route, {
    escalate: "escalate",
    specialist: "specialist",
    knowledge_answer: "knowledge_answer"
  }

  validates :name, :terms, :category, :priority_level, :reasoning_summary, presence: true

  scope :active_first, -> { where(active: true).order(:priority, :id) }
  scope :routing_rules, -> { where(blocks_public_knowledge: false) }
  scope :knowledge_blockers, -> { where(blocks_public_knowledge: true) }

  def term_list
    terms.to_s.lines.map(&:strip).reject(&:blank?)
  end
end
