module PublicKnowledge
  class SiteImporter
    def initialize(company:, root_url:, fetcher: nil)
      @company = company
      @root_url = root_url
      @fetcher = fetcher
    end

    def call
      root_html = fetch(@root_url)
      import_source(@root_url, html: root_html)

      LinkDiscoverer.new(root_url: @root_url, html: root_html).call.each do |url|
        next if url == @root_url

        import_source(url)
      end
    end

    private

    def import_source(url, html: nil)
      source = @company.knowledge_sources.find_or_create_by!(url: url) do |record|
        record.source_kind = "website_page"
        record.status = "pending"
      end

      Importer.new(source: source, html: html, fetcher: @fetcher).call
    end

    def fetch(url)
      return @fetcher.call(url) if @fetcher

      URI.parse(url).open.read
    end
  end
end
