require "set"

#TODO: replace by a proper RAG search

module PublicKnowledge
  class Retriever
    Match = Struct.new(:chunk, :score, keyword_init: true)
    MAX_RESULTS = 3
    MANUAL_ENTRY_BONUS = 3
    TITLE_TERM_WEIGHT = 2
    PHRASE_MATCH_WEIGHT = 3
    TITLE_PHRASE_MATCH_WEIGHT = 6
    SPECIFIC_TOPIC_MATCH_WEIGHT = 4
    MIN_TERM_LENGTH = 3
    SHORT_TERM_ALLOWLIST = %w[uk us eu uae].freeze
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
      "privacy" => %w[privacy deleted delete deletion retention retain kept keep stored storage remove erase upload uploaded],
      "delete" => %w[deleted deletion remove erase uploaded upload photos],
      "deleted" => %w[delete deletion remove erase uploaded upload photos],
      "retention" => %w[retain kept keep stored storage deleted delete photos],
      "retain" => %w[retention kept keep stored storage deleted delete photos],
      "keep" => %w[retention retain kept stored storage deleted delete photos],
      "stored" => %w[storage retain retention keep kept deleted delete photos],
      "picture" => %w[photo],
      "photos" => %w[photo],
      "visa" => %w[visa],
      "germany" => %w[germany german],
      "german" => %w[germany german],
      "us" => %w[us usa united-states american],
      "united states" => %w[united-states us usa american],
      "uk" => %w[uk united-kingdom britain british],
      "human" => %w[human agent person],
      "escalate" => %w[handoff hand-off transfer]
    }.freeze
    PRIVACY_TERMS = %w[
      privacy delete deleted deletion remove erase retention retain keep kept stored storage upload uploaded photo photos
    ].freeze
    COUNTRY_TERMS = {
      "us" => %w[us usa united-states american],
      "germany" => %w[germany german],
      "canada" => %w[canada canadian],
      "uk" => %w[uk united-kingdom britain british],
      "india" => %w[india indian]
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
      matched_terms = terms.select { |term| content_terms.include?(term) || title_terms.include?(term) }

      content_score = terms.sum { |term| content_terms.include?(term) ? term_weight(term) : 0 }
      title_score = terms.sum { |term| title_terms.include?(term) ? term_weight(term) * TITLE_TERM_WEIGHT : 0 }
      phrase_score = phrases.sum do |phrase|
        bonus = 0
        bonus += PHRASE_MATCH_WEIGHT if content_text.include?(phrase)
        bonus += PHRASE_MATCH_WEIGHT * TITLE_TERM_WEIGHT if title_text.include?(phrase)
        bonus
      end
      title_phrase_score = title_phrase_bonus(title_text)
      specific_topic_score = specific_topic_bonus(content_terms, title_terms, title_text)
      manual_bonus = chunk.manual_entry.present? ? MANUAL_ENTRY_BONUS : 0

      return 0 unless substantive_match?(matched_terms, phrase_score)
      return 0 if privacy_query? && !privacy_match?(content_terms, title_terms)
      return 0 if specific_country_query? && !specific_country_match?(content_terms, title_terms)

      content_score + title_score + phrase_score + title_phrase_score + specific_topic_score + manual_bonus
    end

    def normalized_query_terms
      @query.scan(/[a-z0-9-]+/)
    end

    def token_set(text)
      normalize_text(text).scan(/[a-z0-9-]+/).to_set
    end

    def normalize_text(text)
      text.to_s.downcase
        .gsub("united states", "united-states")
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

    def company_name_terms
      @company_name_terms ||= @company.name.to_s.downcase.scan(/[a-z0-9-]+/).to_set
    end

    def substantive_match?(matched_terms, phrase_score)
      phrase_score.positive? || matched_terms.any? { |term| !company_name_terms.include?(term) }
    end

    def title_phrase_bonus(title_text)
      query_title_terms.sum do |term|
        title_text.include?(term) ? TITLE_PHRASE_MATCH_WEIGHT : 0
      end
    end

    def specific_topic_bonus(content_terms, title_terms, title_text)
      bonus = 0
      bonus += SPECIFIC_TOPIC_MATCH_WEIGHT if privacy_query? && privacy_match?(content_terms, title_terms)

      if specific_country_query? && specific_country_match?(content_terms, title_terms)
        bonus += SPECIFIC_TOPIC_MATCH_WEIGHT
        bonus += SPECIFIC_TOPIC_MATCH_WEIGHT if specific_country_title_match?(title_text)
      end

      bonus
    end

    def privacy_query?
      (expanded_terms & PRIVACY_TERMS).any?
    end

    def privacy_match?(content_terms, title_terms)
      ((content_terms | title_terms) & PRIVACY_TERMS).any?
    end

    def specific_country_query?
      specific_country_terms.any?
    end

    def specific_country_match?(content_terms, title_terms)
      expected = specific_country_terms
      expected.any? && ((content_terms | title_terms) & expected).any?
    end

    def specific_country_title_match?(title_text)
      specific_country_terms.any? { |term| title_text.include?(term) }
    end

    def specific_country_terms
      @specific_country_terms ||= COUNTRY_TERMS.each_with_object(Set.new) do |(query_term, expansions), set|
        next unless @query.include?(query_term)

        expansions.each { |term| set << term }
      end
    end

    def query_title_terms
      @query_title_terms ||= begin
        terms = []
        terms.concat(specific_country_terms.to_a)
        terms.concat(%w[deletion retention privacy turnaround]) if privacy_query?
        terms.uniq
      end
    end
  end
end
