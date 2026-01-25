require "json"
require "net/http"
require "uri"

module Osv
  class Client
    class Error < StandardError; end

    URL = "https://api.osv.dev/v1/query"

    def initialize(http: Net::HTTP)
      @http = http
    end

    # Returns parsed JSON response (hash). Example keys:
    # - "vulns" => [ { "id" => "...", ... }, ... ]
    def query_rubygems(gem_name:, version:)
      uri = URI.parse(URL)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = {
        package: { name: gem_name, ecosystem: "RubyGems" },
        version: version
      }.to_json

      response = @http.start(uri.host, uri.port, use_ssl: uri.scheme == "https") { |h| h.request(request) }
      raise Error, "osv request failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue JSON::ParserError => e
      raise Error, "osv returned invalid JSON: #{e.message}"
    end
  end
end
