require "net/http"
require "rss"
require "uri"

module RubyLang
  class NewsRss
    class FetchError < StandardError; end

    URL = "https://www.ruby-lang.org/en/feeds/news.rss"

    def initialize(http: Net::HTTP)
      @http = http
    end

    def find_announcement_url_by_cve(cve)
      return nil if cve.blank?

      feed = fetch_feed
      item = feed.items.find do |i|
        [ i.title, i.description, i.respond_to?(:content_encoded) ? i.content_encoded : nil ].compact.join("\n").include?(cve)
      end

      item&.link
    rescue FetchError, RSS::Error
      nil
    end

    private
      def fetch_feed
        uri = URI.parse(URL)
        response = @http.get_response(uri)
        raise FetchError, "ruby-lang rss request failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        RSS::Parser.parse(response.body, false)
      end
  end
end
