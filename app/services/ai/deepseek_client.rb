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

      JSON.parse(strip_markdown_fences(content))
    rescue JSON::ParserError => e
      raise Error, "deepseek returned invalid JSON: #{e.message}"
    end

    private
      # LLMs sometimes wrap JSON in markdown code fences despite instructions.
      # Strip ```json ... ``` or ``` ... ``` wrappers.
      def strip_markdown_fences(text)
        text = text.strip
        if text.start_with?("```")
          # Remove opening fence (```json or ```)
          text = text.sub(/\A```\w*\s*\n?/, "")
          # Remove closing fence
          text = text.sub(/\n?```\s*\z/, "")
        end
        text.strip
      end
  end
end
