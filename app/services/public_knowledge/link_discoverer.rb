module PublicKnowledge
  class LinkDiscoverer
    def initialize(root_url:, html:)
      @root_url = root_url
      @html = html.to_s
    end

    def call
      body_links
        .filter_map { |href| normalize_link(href) }
        .uniq
        .sort
    end

    private

    def body_links
      document = Nokogiri::HTML.parse(@html)
      body = document.at("body")
      return [] unless body

      body.css("a[href]").map { |node| node["href"] }
    end

    def normalize_link(href)
      return if href.blank?
      return if href.start_with?("#", "mailto:", "tel:", "javascript:")

      uri = URI.join(@root_url, href)
      return unless uri.host == root_uri.host
      return unless %w[http https].include?(uri.scheme)

      uri.fragment = nil
      uri.query = nil
      uri.to_s
    rescue URI::InvalidURIError
      nil
    end

    def root_uri
      @root_uri ||= URI.parse(@root_url)
    end
  end
end
