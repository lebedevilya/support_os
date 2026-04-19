module ApplicationHelper
  URL_PATTERN = %r{https?://[^\s<]+}.freeze

  def linked_message_content(text)
    safe_join(linkify_segments(text.to_s))
  end

  private

  def linkify_segments(text)
    text.split(URL_PATTERN).zip(text.scan(URL_PATTERN)).flat_map do |plain_text, url|
      parts = []
      parts << ERB::Util.html_escape(plain_text) if plain_text.present?
      if url.present?
        parts << link_to(
          url,
          url,
          target: "_blank",
          rel: "noopener noreferrer",
          class: "text-sky-700 underline underline-offset-2"
        )
      end
      parts
    end.compact
  end
end
