module PublicKnowledge
  class Chunker
    MAX_WORDS = 45

    def initialize(text:)
      @text = text.to_s
    end

    def call
      words = @text.split
      return [] if words.empty?

      words.each_slice(MAX_WORDS).map { |slice| slice.join(" ") }
    end
  end
end
