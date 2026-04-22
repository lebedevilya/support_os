module PublicKnowledge
  class AnswerComposer
    YES_NO_PREFIXES = /\A\s*(can|could|do|does|is|are|will|would)\b/i
    STOPWORDS = %w[
      a an and are can could do does for get help here how i in it know me my no of
      on or please really service services sure the this to use using we what when
      where why you your
    ].freeze
    TERM_EXPANSIONS = {
      "cost" => %w[price prices pricing],
      "how long" => %w[seconds second minutes minute instant instantly],
      "price" => %w[cost pricing prices],
      "pricing" => %w[price cost prices],
      "take" => %w[seconds second minutes minute instant instantly],
      "takes" => %w[seconds second minutes minute instant instantly],
      "picture" => %w[photo photos]
    }.freeze

    def initialize(question:, chunk:)
      @question = question.to_s.strip
      @chunk = chunk
    end

    def call
      "#{opening} #{chunk_text} Source: #{source_label}."
    end

    private

    def opening
      return "Yes, you can." if yes_no_question?

      "Here’s what I found."
    end

    def yes_no_question?
      @question.match?(YES_NO_PREFIXES)
    end

    def chunk_text
      best_sentence.to_s.strip
    end

    def source_label
      if @chunk.source
        [ @chunk.source.title.presence, @chunk.source.url.presence ].compact.join(" — ")
      elsif @chunk.manual_entry
        @chunk.manual_entry.title
      else
        "public knowledge"
      end
    end

    def best_sentence
      sentences = normalized_sentences
      return @chunk.content.to_s.strip if sentences.empty?

      sentence, score = sentences.map { |candidate| [ candidate, sentence_score(candidate) ] }.max_by(&:last)
      return sentences.first if score.to_i <= 0

      sentence
    end

    def normalized_sentences
      @chunk.content.to_s.split(/(?<=[.!?])\s+/).map(&:strip).reject(&:blank?)
    end

    def sentence_score(sentence)
      text = normalize_text(sentence)
      terms = query_terms

      terms.sum { |term| text.include?(term) ? 1 : 0 } +
        query_phrases.sum { |phrase| text.include?(phrase) ? 2 : 0 }
    end

    def query_terms
      @query_terms ||= begin
        terms = normalize_text(@question).scan(/[a-z0-9-]+/)
        TERM_EXPANSIONS.each do |phrase, expansions|
          next unless normalize_text(@question).include?(phrase)

          terms.concat(expansions)
        end

        terms.filter_map do |term|
          next if STOPWORDS.include?(term)
          next if term.length < 3

          term
        end.uniq
      end
    end

    def query_phrases
      @query_phrases ||= TERM_EXPANSIONS.keys.select { |phrase| normalize_text(@question).include?(phrase) }
    end

    def normalize_text(text)
      text.to_s.downcase
    end
  end
end
