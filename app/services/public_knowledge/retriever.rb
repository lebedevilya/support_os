module PublicKnowledge
  class Retriever
    Match = Struct.new(:chunk, :score, keyword_init: true)
    MAX_RESULTS = 3
    MANUAL_ENTRY_BONUS = 3
    TITLE_TERM_WEIGHT = 2

    TERM_EXPANSIONS = {
      "how long" => %w[seconds second minutes minute instant instantly],
      "take" => %w[seconds second minutes minute instant instantly],
      "support" => %w[support supported available],
      "contact" => %w[contact email reach],
      "guarantee" => %w[guarantee refund money-back],
      "privacy" => %w[privacy deleted delete retention]
    }.freeze

    def initialize(company:, query:)
      @company = company
      @query = query.to_s.downcase
    end

    def call
      matches.map(&:chunk)
    end

    def matches
      candidate_terms = expanded_terms

      @company.knowledge_chunks
        .to_a
        .filter_map do |chunk|
          score = score(chunk, candidate_terms)
          next if score.zero?

          Match.new(chunk: chunk, score: score)
        end
        .sort_by { |match| -match.score }
        .first(MAX_RESULTS)
    end

    private

    def expanded_terms
      terms = @query.scan(/[a-z0-9]+/)
      TERM_EXPANSIONS.each do |phrase, expansions|
        terms.concat(expansions) if @query.include?(phrase)
      end
      terms.uniq
    end

    def score(chunk, terms)
      content = chunk.content.to_s.downcase
      title = [ chunk.source&.title, chunk.manual_entry&.title ].compact.join(" ").downcase

      content_score = terms.sum { |term| content.include?(term) ? 1 : 0 }
      title_score = terms.sum { |term| title.include?(term) ? TITLE_TERM_WEIGHT : 0 }
      manual_bonus = chunk.manual_entry.present? ? MANUAL_ENTRY_BONUS : 0

      content_score + title_score + manual_bonus
    end
  end
end
