module PublicKnowledge
  class Retriever
    Match = Struct.new(:chunk, :score, keyword_init: true)
    MAX_RESULTS = 3

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
          score = score(chunk.content.downcase, candidate_terms)
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

    def score(content, terms)
      terms.sum { |term| content.include?(term) ? 1 : 0 }
    end
  end
end
