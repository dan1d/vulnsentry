require "json"
require "net/http"
require "uri"

module Ai
  class DeepseekClient
    class Error < StandardError; end

    DEFAULT_URL = "https://api.deepseek.com/chat/completions"
    DEFAULT_MODEL = "deepseek-chat"

    def initialize(api_key: ENV["DEEPSEEK_API_KEY"], url: ENV.fetch("DEEPSEEK_API_URL", DEFAULT_URL), model: DEFAULT_MODEL, http: Net::HTTP)
      @api_key = api_key
      @url = url
      @model = model
      @http = http
    end

    def enabled?
      @api_key.present?
    end

    # Returns parsed JSON from the assistant's content, or raises.
    def extract_json!(system:, user:)
      raise Error, "DEEPSEEK_API_KEY not set" unless enabled?

      uri = URI.parse(@url)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Bearer #{@api_key}"
      request.body = {
        model: @model,
        stream: false,
        messages: [
          { role: "system", content: system },
          { role: "user", content: user }
        ]
      }.to_json

      response = @http.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |h|
        h.request(request)
      end

      raise Error, "deepseek request failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      data = JSON.parse(response.body)
      content = data.dig("choices", 0, "message", "content")
      raise Error, "deepseek response missing content" if content.blank?

      JSON.parse(content)
    rescue JSON::ParserError => e
      raise Error, "deepseek returned invalid JSON: #{e.message}"
    end
  end
end
