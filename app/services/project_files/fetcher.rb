# frozen_string_literal: true

require "net/http"
require "uri"

module ProjectFiles
  # Fetches dependency files from GitHub for any project.
  # Supports caching to reduce API calls.
  class Fetcher
    class FetchError < StandardError; end

    # Default cache TTL (30 minutes)
    DEFAULT_CACHE_TTL = 30.minutes

    def initialize(project, cache_ttl: DEFAULT_CACHE_TTL)
      @project = project
      @cache_ttl = cache_ttl
    end

    # Fetch the dependency file content for a branch
    # @param repo [String] Repository in owner/repo format (optional, uses project's repo)
    # @param branch [String] Branch name to fetch from
    # @return [String] File content
    def fetch(repo: nil, branch:)
      repo ||= @project.upstream_repo
      cache_key = build_cache_key(repo, branch)

      Rails.cache.fetch(cache_key, expires_in: @cache_ttl) do
        fetch_from_github(repo, branch)
      end
    end

    # Force fetch without cache
    def fetch!(repo: nil, branch:)
      repo ||= @project.upstream_repo
      fetch_from_github(repo, branch)
    end

    private

    def fetch_from_github(repo, branch)
      url = raw_github_url(repo, branch)
      uri = URI.parse(url)

      response = Net::HTTP.get_response(uri)

      case response
      when Net::HTTPSuccess
        response.body
      when Net::HTTPNotFound
        raise FetchError, "File not found: #{@project.file_path} in #{repo}@#{branch}"
      when Net::HTTPRedirection
        # Follow redirect
        redirect_uri = URI.parse(response["location"])
        redirect_response = Net::HTTP.get_response(redirect_uri)
        if redirect_response.is_a?(Net::HTTPSuccess)
          redirect_response.body
        else
          raise FetchError, "Failed to fetch after redirect: #{redirect_response.code}"
        end
      else
        raise FetchError, "HTTP #{response.code}: #{response.message}"
      end
    rescue SocketError, Timeout::Error, Errno::ECONNREFUSED => e
      raise FetchError, "Network error: #{e.message}"
    end

    def raw_github_url(repo, branch)
      # GitHub raw content URL
      "https://raw.githubusercontent.com/#{repo}/#{branch}/#{@project.file_path}"
    end

    def build_cache_key(repo, branch)
      "project_files:#{@project.slug}:#{repo}:#{branch}:#{@project.file_path}"
    end
  end
end
