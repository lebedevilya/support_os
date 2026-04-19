module ApplicationHelper
  URL_PATTERN = %r{https?://[^\s<]+}.freeze

  def linked_message_content(text)
    safe_join(linkify_segments(text.to_s))
  end

  def format_confidence(value)
    number = value.to_f
    return "n/a" if number <= 0

    "#{(number * 100).round}%"
  end

  def pretty_json(value)
    JSON.pretty_generate(parse_json_like(value))
  rescue JSON::ParserError, TypeError
    value.to_s
  end

  private

  def parse_json_like(value)
    return value if value.is_a?(Hash) || value.is_a?(Array)

    JSON.parse(value.to_s)
  end

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
