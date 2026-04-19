module PublicKnowledge
  class Importer
    def initialize(source:, html: nil, fetcher: nil)
      @source = source
      @html = html
      @fetcher = fetcher
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
      return @fetcher.call(@source.url) if @fetcher

      URI.parse(@source.url).open.read
    end

    def extract_text(html)
      document = Nokogiri::HTML.parse(html.to_s)
      root = document.at("body") || document

      root.css("script, style, noscript, template, svg, iframe").remove
      root.css("[aria-hidden='true']").remove
      root.css("[hidden]").each do |node|
        next if node["id"].to_s.match?(/\AS:\d+\z/)

        node.remove
      end

      text = ActionView::Base.full_sanitizer.sanitize(root.to_html)
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
