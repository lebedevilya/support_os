module PublicKnowledge
  class AnswerComposer
    YES_NO_PREFIXES = /\A\s*(can|could|do|does|is|are|will|would)\b/i

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
      @chunk.content.to_s.strip
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
  end
end
