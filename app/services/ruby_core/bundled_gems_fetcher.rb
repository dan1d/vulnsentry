require "net/http"
require "uri"

module RubyCore
  class BundledGemsFetcher
    class FetchError < StandardError; end

    PATH = "gems/bundled_gems"

    def initialize(http: Net::HTTP)
      @http = http
    end

    def fetch(repo:, branch:)
      owner, name = repo.split("/", 2)
      raise FetchError, "invalid repo: #{repo.inspect}" unless owner.present? && name.present?

      url = "https://raw.githubusercontent.com/#{owner}/#{name}/#{branch}/#{PATH}"
      uri = URI.parse(url)
      response = @http.get_response(uri)
      raise FetchError, "bundled_gems fetch failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)
      response.body
    end
  end
end
