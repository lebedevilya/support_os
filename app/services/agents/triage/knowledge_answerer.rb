module Agents
  module Triage
    class KnowledgeAnswerer
      GROUNDED_REPLY_UNSUPPORTED_RATIO = 0.35
      GROUNDED_REPLY_MIN_UNSUPPORTED_TOKENS = 3
      GROUNDING_STOPWORDS = %w[
        a an and are at but by can details for from help here how i if in is it its know
        located me my of on or our please the their they this to us want what where with
        you your
      ].freeze

      include Agents::Shared::Normalizers

      def initialize(ticket:, llm_client:)
        @ticket = ticket
        @llm_client = llm_client
      end

      def call(matches)
        response = @llm_client.complete_json(
          task: "knowledge_answer",
          prompt: Prompts::KNOWLEDGE_ANSWER,
          context: {
            company: @ticket.company.name,
            latest_message: latest_message.content,
            message_history: message_history,
            knowledge_chunks: matches.map do |match|
              {
                content: match.chunk.content,
                score: match.score,
                source_title: match.chunk.source&.title,
                source_url: match.chunk.source&.url,
                manual_entry_title: match.chunk.manual_entry&.title
              }
            end
          }
        )

        return nil if response[:reply].to_s.strip.empty?
        return nil if unsupported_reply?(response, matches)

        {
          source: "public_knowledge_llm",
          status: "awaiting_customer",
          category: "policy",
          priority: "normal",
          route: "knowledge_answer",
          current_layer: "triage",
          confidence: numeric_confidence(response[:confidence]),
          decision: "knowledge_answer",
          reply: compose_reply(response[:reply], response[:cited_source_url], matches),
          reasoning_summary: response[:reasoning_summary].presence || "Answered from public knowledge with LLM synthesis.",
          input_snapshot: latest_message.content,
          tags: normalized_tags(response[:tags], fallback_tags: knowledge_tags(matches))
        }
      rescue StandardError
        nil
      end

      private

      def latest_message
        @latest_message ||= @ticket.messages.order(:created_at).last
      end

      def message_history
        @message_history ||= @ticket.messages.order(:created_at).pluck(:role, :content)
      end

      def compose_reply(reply, cited_source_url, matches)
        reply_text = reply.to_s.strip
        return reply_text if reply_text.blank?

        source_url = validated_cited_url(cited_source_url, matches)
        return reply_text unless source_url

        "#{reply_text} Source: #{source_url}"
      end

      def validated_cited_url(cited_source_url, matches)
        candidate = cited_source_url.to_s.strip
        return if candidate.blank?
        return if matches.first.chunk.manual_entry.present?

        allowed_urls = matches.filter_map { |match| match.chunk.source&.url.presence }.uniq
        allowed_urls.include?(candidate) ? candidate : nil
      end

      def unsupported_reply?(response, matches)
        reply_tokens = grounding_tokens(response[:reply])
        return false if reply_tokens.empty?

        supported_tokens = grounding_tokens(latest_message.content)
        matches.each { |match| supported_tokens.merge(grounding_tokens(match.chunk.content)) }

        unsupported = reply_tokens - supported_tokens
        return false if unsupported.size < GROUNDED_REPLY_MIN_UNSUPPORTED_TOKENS

        unsupported.size.to_f / reply_tokens.size > GROUNDED_REPLY_UNSUPPORTED_RATIO
      end

      def grounding_tokens(text)
        text.to_s.downcase.scan(/[a-z0-9-]+/).filter_map do |token|
          next if token.length < 4 && token !~ /\A\d+\z/
          next if GROUNDING_STOPWORDS.include?(token)

          token
        end.to_set
      end

      def knowledge_tags(matches)
        matches.flat_map { |match| chunk_tags(match.chunk) }.uniq
      end

      def chunk_tags(chunk)
        [
          "public-knowledge",
          "knowledge-answer",
          "policy",
          normalize_tag(chunk.source&.title),
          normalize_tag(chunk.manual_entry&.title)
        ].compact.uniq
      end
    end
  end
end
