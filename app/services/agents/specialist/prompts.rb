module Agents
  module Specialist
    module Prompts
      POLICY = <<~PROMPT.freeze
        Draft a customer-facing support reply.
        Return keys:
        - reply: string
        - resolve_ticket: boolean
        - confidence: decimal between 0 and 1
        - used_knowledge_articles: array of strings
        - used_tools: array of strings
        - reasoning_summary: short sentence
        - tags: array of strings
        Use only the provided knowledge and do not invent policies.
      PROMPT

      GENERAL = <<~PROMPT.freeze
        Draft a customer-facing support reply.
        Return keys:
        - reply: string
        - resolve_ticket: boolean
        - confidence: decimal between 0 and 1
        - used_knowledge_articles: array of strings
        - used_tools: array of strings
        - reasoning_summary: short sentence
        - tags: array of strings
        Use only the provided knowledge and tool results.
        Do not claim any operational action happened unless the tool results explicitly show that action happened.
        If an action tool ran successfully, say what happened and what the customer should expect next.
        If the case is ambiguous or unsafe, set resolve_ticket to false.
      PROMPT

      def self.action_choice(allowed_actions:)
        <<~PROMPT
          Choose the next specialist action.
          Return keys:
          - action: one of #{allowed_actions.join(", ")}
          - reasoning_summary: short sentence
          Rules:
          - only choose a listed action
          - choose an action only when the customer clearly asked for it and the provided record state supports it
          - choose escalate when the request is unsafe or the record state is ambiguous
          - choose none when a lookup-backed reply is enough
        PROMPT
      end
    end
  end
end
