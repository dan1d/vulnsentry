require "json"
require "net/http"
require "uri"

module Ai
  class DeepseekClient
    class Error < StandardError; end
    class RateLimitError < Error; end
    class TimeoutError < Error; end

    DEFAULT_URL = "https://api.deepseek.com/chat/completions"
    DEFAULT_MODEL = "deepseek-chat"
    DEFAULT_TEMPERATURE = 0.1
    DEFAULT_MAX_RETRIES = 3
    DEFAULT_TIMEOUT = 30

    # Retry configuration
    RETRYABLE_ERRORS = [
      Net::OpenTimeout,
      Net::ReadTimeout,
      Errno::ECONNRESET,
      Errno::ECONNREFUSED,
      Errno::ETIMEDOUT,
      SocketError,
      RateLimitError
    ].freeze
    BASE_DELAY = 1.0 # seconds
    MAX_DELAY = 30.0 # seconds

    def initialize(
      api_key: ENV["DEEPSEEK_API_KEY"],
      url: ENV.fetch("DEEPSEEK_API_URL", DEFAULT_URL),
      model: DEFAULT_MODEL,
      http: Net::HTTP,
      temperature: DEFAULT_TEMPERATURE,
      max_retries: DEFAULT_MAX_RETRIES,
      timeout: DEFAULT_TIMEOUT,
      logger: Rails.logger
    )
      @api_key = api_key
      @url = url
      @model = model
      @http = http
      @temperature = temperature
      @max_retries = max_retries
      @timeout = timeout
      @logger = logger
    end

    def enabled?
      @api_key.present?
    end

    # Returns parsed JSON from the assistant's content, or raises.
    # Includes retry logic with exponential backoff and request/response logging.
    def extract_json!(system:, user:)
      raise Error, "DEEPSEEK_API_KEY not set - configure the API key in environment variables" unless enabled?

      request_id = SecureRandom.uuid
      attempt = 0
      last_error = nil

      log_request(request_id, system, user)

      while attempt < @max_retries
        attempt += 1

        begin
          result = perform_request(system: system, user: user, request_id: request_id, attempt: attempt)
          log_response(request_id, result, attempt)
          return result
        rescue *RETRYABLE_ERRORS => e
          last_error = e
          delay = calculate_delay(attempt)

          log_retry(request_id, attempt, e, delay)

          if attempt < @max_retries
            sleep(delay)
          end
        rescue Error => e
          # Non-retryable errors: log and re-raise immediately
          log_error(request_id, e, attempt, retryable: false)
          raise
        end
      end

      # All retries exhausted
      error = Error.new("DeepSeek API failed after #{@max_retries} attempts: #{last_error&.message}")
      log_error(request_id, error, attempt, retryable: true)
      raise error
    end

    private

    def perform_request(system:, user:, request_id:, attempt:)
      uri = URI.parse(@url)
      request = build_request(uri, system, user)

      response = @http.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |h|
        h.open_timeout = @timeout
        h.read_timeout = @timeout
        h.request(request)
      end

      handle_response(response, request_id)
    end

    def build_request(uri, system, user)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Bearer #{@api_key}"
      request.body = {
        model: @model,
        stream: false,
        temperature: @temperature,
        messages: [
          { role: "system", content: system },
          { role: "user", content: user }
        ]
      }.to_json
      request
    end

    def handle_response(response, request_id)
      case response
      when Net::HTTPSuccess
        parse_successful_response(response)
      when Net::HTTPTooManyRequests
        raise RateLimitError, "Rate limited by DeepSeek API (429)"
      when Net::HTTPServerError
        raise Error, "DeepSeek server error: #{response.code} #{response.message}"
      when Net::HTTPUnauthorized
        raise Error, "DeepSeek API authentication failed (401) - check your API key"
      when Net::HTTPForbidden
        raise Error, "DeepSeek API access forbidden (403) - check your API permissions"
      when Net::HTTPBadRequest
        raise Error, "DeepSeek API bad request (400): #{extract_error_message(response)}"
      else
        raise Error, "DeepSeek API request failed: #{response.code} #{response.message}"
      end
    end

    def parse_successful_response(response)
      data = JSON.parse(response.body)
      content = data.dig("choices", 0, "message", "content")

      if content.blank?
        raise Error, "DeepSeek response missing content - the model returned an empty response"
      end

      # Extract usage metrics for logging
      @last_usage = data["usage"]

      JSON.parse(strip_markdown_fences(content))
    rescue JSON::ParserError => e
      raise Error, "DeepSeek returned invalid JSON: #{e.message}. Raw content: #{content&.truncate(200)}"
    end

    def extract_error_message(response)
      data = JSON.parse(response.body)
      data.dig("error", "message") || response.body.truncate(200)
    rescue JSON::ParserError
      response.body.truncate(200)
    end

    def calculate_delay(attempt)
      # Exponential backoff with jitter
      delay = BASE_DELAY * (2 ** (attempt - 1))
      delay = [ delay, MAX_DELAY ].min
      # Add jitter (0-25% of delay)
      delay + (rand * delay * 0.25)
    end

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

    # ========== Logging Methods ==========

    def log_request(request_id, system, user)
      @logger.info("[DeepseekClient] Request #{request_id}: model=#{@model}, temperature=#{@temperature}")

      SystemEvent.create!(
        kind: "deepseek_request",
        status: "ok",
        occurred_at: Time.current,
        message: "DeepSeek API request initiated",
        payload: {
          request_id: request_id,
          model: @model,
          temperature: @temperature,
          system_prompt_length: system.length,
          user_prompt_length: user.length,
          # Store truncated prompts for debugging (avoid huge payloads)
          system_prompt_preview: system.truncate(500),
          user_prompt_preview: user.truncate(1000)
        }
      )
    rescue => e
      @logger.warn("[DeepseekClient] Failed to log request: #{e.message}")
    end

    def log_response(request_id, result, attempt)
      @logger.info("[DeepseekClient] Response #{request_id}: success on attempt #{attempt}")

      SystemEvent.create!(
        kind: "deepseek_response",
        status: "ok",
        occurred_at: Time.current,
        message: "DeepSeek API request successful",
        payload: {
          request_id: request_id,
          attempt: attempt,
          usage: @last_usage,
          response_keys: result.is_a?(Hash) ? result.keys : "array[#{result.size}]"
        }
      )
    rescue => e
      @logger.warn("[DeepseekClient] Failed to log response: #{e.message}")
    end

    def log_retry(request_id, attempt, error, delay)
      @logger.warn("[DeepseekClient] Request #{request_id} attempt #{attempt} failed: #{error.class} - #{error.message}. Retrying in #{delay.round(2)}s")

      SystemEvent.create!(
        kind: "deepseek_retry",
        status: "warning",
        occurred_at: Time.current,
        message: "DeepSeek API request failed, retrying",
        payload: {
          request_id: request_id,
          attempt: attempt,
          error_class: error.class.name,
          error_message: error.message.truncate(500),
          retry_delay: delay.round(2),
          max_retries: @max_retries
        }
      )
    rescue => e
      @logger.warn("[DeepseekClient] Failed to log retry: #{e.message}")
    end

    def log_error(request_id, error, attempt, retryable:)
      @logger.error("[DeepseekClient] Request #{request_id} failed: #{error.class} - #{error.message}")

      SystemEvent.create!(
        kind: "deepseek_error",
        status: "failed",
        occurred_at: Time.current,
        message: "DeepSeek API request failed",
        payload: {
          request_id: request_id,
          attempt: attempt,
          error_class: error.class.name,
          error_message: error.message.truncate(500),
          retryable: retryable,
          max_retries: @max_retries
        }
      )
    rescue => e
      @logger.warn("[DeepseekClient] Failed to log error: #{e.message}")
    end
  end
end
