require "set"

#TODO: replace by a proper RAG search

module PublicKnowledge
  class Retriever
    Match = Struct.new(:chunk, :score, keyword_init: true)
    MAX_RESULTS = 3
    MANUAL_ENTRY_BONUS = 1
    TITLE_TERM_WEIGHT = 2
    PHRASE_MATCH_WEIGHT = 3
    MIN_TERM_LENGTH = 3
    SHORT_TERM_ALLOWLIST = %w[uk us eu uae].freeze
    STOPWORDS = %w[
      a an and are can could do does for get here i in it me my no of on or please
      really sure the this to we what when where why you your
    ].freeze

    TERM_EXPANSIONS = {
      "how long" => %w[seconds second minutes minute instant instantly],
      "take" => %w[seconds second minutes minute instant instantly],
      "support" => %w[support supported available],
      "payment" => %w[payments card cards billing visa mastercard amex apple-pay google-pay],
      "payments" => %w[payment card cards billing visa mastercard amex apple-pay google-pay],
      "system" => %w[method methods options],
      "systems" => %w[method methods options],
      "contact" => %w[contact email reach],
      "office" => [ "address", "registered", "location", "company", "information", "registered address", "company information" ],
      "location" => [ "address", "registered", "office", "company", "information", "registered address", "company information" ],
      "address" => [ "registered", "location", "office", "company", "information", "registered address", "company information" ],
      "guarantee" => %w[guarantee refund money-back],
      "privacy" => %w[privacy deleted delete retention],
      "picture" => %w[photo],
      "photos" => %w[photo],
      "visa" => %w[visa],
      "uk" => %w[uk united-kingdom britain british],
      "human" => %w[human agent person],
      "escalate" => %w[handoff hand-off transfer]
    }.freeze

    def initialize(company:, query:)
      @company = company
      @raw_query = query.to_s.downcase
      @query = normalize_text(@raw_query)
    end

    def call
      matches.map(&:chunk)
    end

    def matches
      candidate_terms = expanded_terms
      candidate_phrases = expanded_phrases

      @company.knowledge_chunks
        .to_a
        .filter_map do |chunk|
          score = score(chunk, candidate_terms, candidate_phrases)
          next if score.zero?

          Match.new(chunk: chunk, score: score)
        end
        .sort_by { |match| -match.score }
        .first(MAX_RESULTS)
    end

    private

    def expanded_terms
      terms = normalized_query_terms.dup
      TERM_EXPANSIONS.each do |phrase, expansions|
        next unless @query.include?(phrase)

        terms.concat(expansions.flat_map { |expansion| expansion.to_s.split(/\s+/) })
      end
      terms
        .map { |term| normalize_term(term) }
        .compact
        .uniq
    end

    def expanded_phrases
      TERM_EXPANSIONS.each_with_object([]) do |(phrase, expansions), phrases|
        next unless @query.include?(phrase)

        phrases.concat(expansions.select { |expansion| expansion.to_s.include?(" ") })
      end.map { |phrase| normalize_phrase(phrase) }.compact.uniq
    end

    def score(chunk, terms, phrases)
      content_text = normalize_text(chunk.content)
      title_text = normalize_text([ chunk.source&.title, chunk.manual_entry&.title ].compact.join(" "))
      content_terms = token_set(content_text)
      title_terms = token_set(title_text)

      content_score = terms.sum { |term| content_terms.include?(term) ? term_weight(term) : 0 }
      title_score = terms.sum { |term| title_terms.include?(term) ? term_weight(term) * TITLE_TERM_WEIGHT : 0 }
      phrase_score = phrases.sum do |phrase|
        bonus = 0
        bonus += PHRASE_MATCH_WEIGHT if content_text.include?(phrase)
        bonus += PHRASE_MATCH_WEIGHT * TITLE_TERM_WEIGHT if title_text.include?(phrase)
        bonus
      end
      manual_bonus = chunk.manual_entry.present? ? MANUAL_ENTRY_BONUS : 0

      content_score + title_score + phrase_score + manual_bonus
    end

    def normalized_query_terms
      @query.scan(/[a-z0-9-]+/)
    end

    def token_set(text)
      normalize_text(text).scan(/[a-z0-9-]+/).to_set
    end

    def normalize_text(text)
      text.to_s.downcase
        .gsub("united kingdom", "united-kingdom")
        .gsub("money back", "money-back")
    end

    def normalize_term(term)
      candidate = term.to_s.strip.downcase
      return if candidate.blank?
      return if STOPWORDS.include?(candidate)
      return if candidate.length < MIN_TERM_LENGTH && !SHORT_TERM_ALLOWLIST.include?(candidate)

      candidate
    end

    def normalize_phrase(phrase)
      candidate = normalize_text(phrase).strip
      candidate.presence
    end

    def term_weight(term)
      SHORT_TERM_ALLOWLIST.include?(term) ? 4 : 1
    end
  end
end
