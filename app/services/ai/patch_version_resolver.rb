module Ai
  class PatchVersionResolver
    class Recommendation
      attr_reader :recommended_version, :confidence, :reasoning,
                  :excluded_advisories, :exclusion_reason

      def initialize(data)
        @recommended_version = data["recommended_version"]
        @confidence = data["confidence"] || "low"
        @reasoning = data["reasoning"]
        @excluded_advisories = data["excluded_advisories"] || []
        @exclusion_reason = data["exclusion_reason"]
      end

      def confident?
        %w[high medium].include?(confidence)
      end

      def to_h
        {
          recommended_version: recommended_version,
          confidence: confidence,
          reasoning: reasoning,
          excluded_advisories: excluded_advisories,
          exclusion_reason: exclusion_reason
        }
      end
    end

    SYSTEM_PROMPT = <<~PROMPT
      You are a security patch version resolver for Ruby gems.
      Your job is to determine the minimum gem version that fixes all listed security advisories.

      Rules:
      1. Prefer patch-level bumps (e.g., 3.2.5 → 3.2.7) over minor or major bumps
      2. Maintenance branches (ruby_3_0, ruby_3_1, etc.) should be conservative
      3. Pick the MINIMUM version that covers ALL advisories when possible
      4. If some advisories require a major/minor bump while others only need a patch, flag for manual review
      5. If all suggested versions are compatible (same major.minor), pick the highest

      Respond ONLY with valid JSON, no markdown fences or explanation outside JSON.
    PROMPT

    USER_PROMPT_TEMPLATE = <<~PROMPT
      Analyze these security advisories for gem version resolution:

      Branch: %{base_branch}
      Gem: %{gem_name}
      Current version: %{current_version}

      Advisories and their suggested fix versions:
      %{advisories_summary}

      Determine the optimal target version.

      JSON response format:
      {
        "recommended_version": "1.2.3",
        "confidence": "high|medium|low",
        "reasoning": "explanation of why this version was chosen",
        "excluded_advisories": ["CVE-xxx"],
        "exclusion_reason": "reason if any advisories are excluded"
      }
    PROMPT

    def initialize(client: Ai::DeepseekClient.new)
      @client = client
    end

    def enabled?
      @client.enabled?
    end

    def resolve(gem_name:, base_branch:, current_version:, bundled_advisories:)
      return fallback_resolution(current_version, bundled_advisories) unless enabled?

      user_prompt = format(
        USER_PROMPT_TEMPLATE,
        base_branch: base_branch,
        gem_name: gem_name,
        current_version: current_version,
        advisories_summary: format_advisories(bundled_advisories)
      )

      result = @client.extract_json!(system: SYSTEM_PROMPT, user: user_prompt)
      Recommendation.new(result)
    rescue Ai::DeepseekClient::Error => e
      Rails.logger.error("[PatchVersionResolver] LLM error: #{e.message}")
      fallback_resolution(current_version, bundled_advisories)
    end

    private

    def format_advisories(bundled_advisories)
      bundled_advisories.map do |ba|
        advisory = ba.advisory
        version = ba.suggested_fix_version || "(unknown)"
        "- #{advisory.cve || advisory.fingerprint} (#{advisory.source}): suggests #{version}"
      end.join("\n")
    end

    def fallback_resolution(current_version, bundled_advisories)
      # Simple fallback: pick highest suggested version if all compatible
      versions = bundled_advisories.map(&:suggested_fix_version).compact
      return Recommendation.new({ "confidence" => "low", "reasoning" => "No fix versions available" }) if versions.empty?

      current = Gem::Version.new(current_version)
      parsed = versions.map { |v| Gem::Version.new(v) rescue nil }.compact

      # Check if all versions are patch-level compatible with current
      current_minor = "#{current.segments[0]}.#{current.segments[1]}"
      all_patch_level = parsed.all? do |v|
        "#{v.segments[0]}.#{v.segments[1]}" == current_minor
      end

      if all_patch_level
        highest = parsed.max
        Recommendation.new({
          "recommended_version" => highest.to_s,
          "confidence" => "high",
          "reasoning" => "All advisories fixed by patch-level bump to #{highest}"
        })
      else
        Recommendation.new({
          "recommended_version" => parsed.max.to_s,
          "confidence" => "low",
          "reasoning" => "Mixed version requirements, needs manual review"
        })
      end
    end
  end
end
