require "net/http"
require "uri"

module RubyLang
  class SecurityAdvisoryResolver
    class FetchError < StandardError; end

    def initialize(rss: NewsRss.new, http: Net::HTTP, ai_client: Ai::DeepseekClient.new)
      @rss = rss
      @http = http
      @ai_client = ai_client
    end

    # Returns a fixed version string or nil.
    #
    # Best practice:
    # - Prefer ruby-lang page fixed version if deterministically parsed.
    # - If parse fails and AI fallback is enabled, ask DeepSeek to extract fixed version (strict JSON) and validate it.
    # - Otherwise return fallback_fixed_version.
    def resolve_fixed_version(gem_name:, current_version:, cve:, fallback_fixed_version:)
      url = @rss.find_announcement_url_by_cve(cve)
      return fallback_fixed_version if url.blank?

      html = fetch_html(url)

      fixed = SecurityAnnouncementParser.extract_fixed_version_for_gem(html: html, gem_name: gem_name)
      fixed = ai_extract_fixed_version(html: html, gem_name: gem_name) if fixed.blank? && ai_fallback_enabled?

      return fallback_fixed_version if fixed.blank?
      return fallback_fixed_version unless newer_version?(fixed, current_version)

      fixed
    rescue FetchError, RubyLang::SecurityAnnouncementParser::ParseError => e
      SystemEvent.create!(
        kind: "ruby_lang_resolver",
        status: "warning",
        message: e.message,
        payload: { cve: cve, gem_name: gem_name },
        occurred_at: Time.current
      )
      fallback_fixed_version
    end

    private
      def fetch_html(url)
        uri = URI.parse(url)
        response = @http.get_response(uri)
        raise FetchError, "ruby-lang fetch failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)
        response.body
      end

      def newer_version?(candidate, current)
        Gem::Version.new(candidate) > Gem::Version.new(current)
      rescue ArgumentError
        false
      end

      def ai_fallback_enabled?
        ENV["ENABLE_DEEPSEEK_RUBYLANG_FALLBACK"].to_s == "true" && @ai_client.enabled?
      end

      def ai_extract_fixed_version(html:, gem_name:)
        system = <<~SYS
          You extract security advisory info from HTML.
          Return ONLY valid JSON. No markdown. No commentary.
          Output schema: {"gem":"<name>","fixed_version":"<version-or-null>"}
        SYS

        user = <<~USER
          Extract the recommended minimum fixed version for the gem "#{gem_name}" from this ruby-lang security announcement HTML.
          If not present, fixed_version should be null.
          Return ONLY JSON.

          HTML:
          #{html}
        USER

        json = @ai_client.extract_json!(system: system, user: user)
        return nil unless json.is_a?(Hash)
        return nil unless json["gem"].to_s.downcase == gem_name.downcase

        json["fixed_version"].presence
      rescue Ai::DeepseekClient::Error
        nil
      end
  end
end
