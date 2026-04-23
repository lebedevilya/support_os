module PublicKnowledge
  class AnswerComposer
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
      "embassy" => %w[embassy rejected rejection refund guarantee],
      "reject" => %w[rejected rejection refund guarantee],
      "rejected" => %w[reject rejection refund guarantee],
      "delete" => %w[deleted deletion remove erase uploaded upload photos],
      "deleted" => %w[delete deletion remove erase uploaded upload photos],
      "retention" => %w[retain kept keep stored storage deleted delete photos],
      "retain" => %w[retention kept keep stored storage deleted delete photos],
      "keep" => %w[retention retain kept stored storage deleted delete photos],
      "germany" => %w[germany german],
      "german" => %w[germany german],
      "us" => %w[us usa united-states american],
      "united states" => %w[united-states us usa american],
      "picture" => %w[photo photos],
      "selfie" => %w[selfie phone computer webcam camera],
      "webcam" => %w[computer webcam selfie camera],
      "camera" => %w[camera selfie webcam phone computer lighting studio],
      "lighting" => %w[lighting camera selfie webcam studio],
      "studio" => %w[studio selfie webcam camera phone computer]
    }.freeze

    def initialize(question:, chunk:)
      @question = question.to_s.strip
      @chunk = chunk
    end

    def call
      res = chunk_text
      res += " " + source_label if source_label
      res
    end

    private

    def chunk_text
      best_sentence.to_s.strip
    end

    def source_label
      [ @chunk.source.title.presence, @chunk.source.url.presence ].compact.join(" — ") if @chunk.source
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
        query_phrases.sum { |phrase| text.include?(phrase) ? 2 : 0 } +
        duration_sentence_bonus(text)
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

    def duration_sentence_bonus(text)
      return 0 unless duration_question?

      bonus = 0
      bonus += 2 if text.include?("under ")
      bonus += 1 if text.include?("most ")
      bonus += 1 if text.include?("completed")
      bonus
    end

    def duration_question?
      normalized_question = normalize_text(@question)
      normalized_question.include?("how long") || normalized_question.include?("take")
    end

    def normalize_text(text)
      text.to_s.downcase.gsub("united states", "united-states")
    end
  end
end
