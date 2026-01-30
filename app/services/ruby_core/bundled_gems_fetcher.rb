require "net/http"
require "uri"

module RubyCore
  class BundledGemsFetcher
    include CacheableApi

    class FetchError < StandardError; end

    PATH = "gems/bundled_gems"

    self.cache_namespace = "ruby_core"

    def initialize(http: Net::HTTP)
      @http = http
    end

    # Fetches the bundled_gems file content for a given repo and branch.
    # Results are cached for 30 minutes by default.
    #
    # @param repo [String] The repository in "owner/name" format
    # @param branch [String] The branch name
    # @param force_refresh [Boolean] Bypass cache and fetch fresh content
    # @return [String] The bundled_gems file content
    def fetch(repo:, branch:, force_refresh: false)
      cached(:bundled_gems, repo, branch, force: force_refresh) do
        fetch_from_github(repo: repo, branch: branch)
      end
    end

    # Invalidates the cache for a specific branch.
    # Useful when we know the bundled_gems file has changed.
    def invalidate(repo:, branch:)
      invalidate_cache(:bundled_gems, repo, branch)
    end

    private

    def fetch_from_github(repo:, branch:)
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
