module PublicKnowledge
  class Importer
    def initialize(source:, html: nil)
      @source = source
      @html = html
    end

    def call
      extracted_text = extract_text(fetch_html)

      ActiveRecord::Base.transaction do
        @source.chunks.delete_all
        @source.update!(
          title: @source.title.presence || inferred_title(extracted_text),
          extracted_text: extracted_text,
          status: "imported",
          imported_at: Time.current,
          last_error: nil
        )

        Chunker.new(text: extracted_text).call.each_with_index do |chunk, index|
          @source.chunks.create!(
            company: @source.company,
            content: chunk,
            position: index,
            token_estimate: estimate_tokens(chunk)
          )
        end
      end

      @source
    rescue StandardError => e
      @source.update!(status: "failed", last_error: e.message)
      raise
    end

    private

    def fetch_html
      return @html if @html.present?

      URI.parse(@source.url).open.read
    end

    def extract_text(html)
      text = ActionView::Base.full_sanitizer.sanitize(html.to_s)
      text.gsub(/[[:space:]]+/, " ").strip
    end

    def inferred_title(text)
      text.split(".").first.to_s.truncate(80)
    end

    def estimate_tokens(chunk)
      (chunk.split.size * 1.3).ceil
    end
  end
end
