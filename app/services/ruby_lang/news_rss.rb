require "net/http"
require "rss"
require "uri"

module RubyLang
  class NewsRss
    include CacheableApi

    class FetchError < StandardError; end

    URL = "https://www.ruby-lang.org/en/feeds/news.rss"

    self.cache_namespace = "ruby_lang"

    def initialize(http: Net::HTTP)
      @http = http
    end

    # Finds the Ruby-lang.org announcement URL for a given CVE.
    # The RSS feed is cached for 1 hour.
    #
    # @param cve [String] The CVE identifier (e.g., "CVE-2024-1234")
    # @param force_refresh [Boolean] Bypass cache and fetch fresh feed
    # @return [String, nil] The announcement URL or nil if not found
    def find_announcement_url_by_cve(cve, force_refresh: false)
      return nil if cve.blank?

      feed = fetch_feed(force_refresh: force_refresh)
      item = feed.items.find do |i|
        [ i.title, i.description, i.respond_to?(:content_encoded) ? i.content_encoded : nil ].compact.join("\n").include?(cve)
      end

      item&.link
    rescue FetchError, RSS::Error
      nil
    end

    private

    def fetch_feed(force_refresh: false)
      cached(:ruby_lang_rss, "news_feed", force: force_refresh) do
        fetch_feed_from_source
      end
    end

    def fetch_feed_from_source
      uri = URI.parse(URL)
      response = @http.get_response(uri)
      raise FetchError, "ruby-lang rss request failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      RSS::Parser.parse(response.body, false)
    end
  end
end
