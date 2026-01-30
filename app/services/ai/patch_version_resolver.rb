module Ai
  class PatchVersionResolver
    class Recommendation
      attr_reader :recommended_version, :confidence, :reasoning,
                  :excluded_advisories, :exclusion_reason, :version_analysis

      def initialize(data)
        @recommended_version = data["recommended_version"]
        @confidence = data["confidence"] || "low"
        @reasoning = data["reasoning"]
        @excluded_advisories = data["excluded_advisories"] || []
        @exclusion_reason = data["exclusion_reason"]
        @version_analysis = data["version_analysis"]
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
          exclusion_reason: exclusion_reason,
          version_analysis: version_analysis
        }.compact
      end
    end

    SYSTEM_PROMPT = <<~PROMPT
      You are an expert security patch version resolver for Ruby gems in the Ruby language repository.
      Your task is to determine the MINIMUM gem version that fixes ALL listed security advisories.

      ## Context
      You are helping automate security patches for Ruby's bundled gems. These patches will be applied
      to maintenance branches of Ruby (e.g., ruby_3_0, ruby_3_1, ruby_3_2, ruby_3_3, ruby_3_4).
      Stability is critical - prefer conservative patch-level bumps.

      ## Decision Rules (in priority order)

      1. **SAFETY FIRST**: Every recommended version MUST fix ALL listed CVEs/advisories.
         Never recommend a version that leaves any vulnerability unpatched.

      2. **PATCH-LEVEL PREFERRED**: Strongly prefer patch-level bumps (e.g., 3.2.5 → 3.2.8).
         - Same major.minor means API compatibility is preserved
         - Lower risk of breaking changes
         - Set confidence="high" when all advisories fixed by patch bump

      3. **MINOR BUMP CAUTION**: If a minor version bump is required (e.g., 3.2.x → 3.3.0):
         - Set confidence="medium" if the API changes are documented as backward-compatible
         - Set confidence="low" if there might be breaking changes
         - Document in reasoning why the minor bump is necessary

      4. **MAJOR BUMP = MANUAL REVIEW**: If any advisory requires a major version bump:
         - Set confidence="low"
         - Add those advisories to excluded_advisories
         - Recommend the highest patch-level version that fixes other advisories

      5. **VERSION SELECTION**: When multiple patch versions exist:
         - Pick the HIGHEST version that satisfies the same major.minor
         - Example: If CVE-A needs 3.2.6 and CVE-B needs 3.2.8, recommend 3.2.8

      6. **MAINTENANCE BRANCH AWARENESS**: For older maintenance branches:
         - Be extra conservative - these branches should only get security fixes
         - Prefer the minimum version that fixes all issues

      ## Output Requirements

      Respond with ONLY valid JSON (no markdown fences, no explanatory text outside JSON).
      The JSON must be parseable as-is.

      Required JSON schema:
      {
        "recommended_version": "X.Y.Z",
        "confidence": "high|medium|low",
        "reasoning": "Clear explanation of version choice",
        "version_analysis": "Analysis of version differences between current and target",
        "excluded_advisories": ["CVE-XXXX-YYYY"],
        "exclusion_reason": "Why these were excluded (if any)"
      }
    PROMPT

    USER_PROMPT_TEMPLATE = <<~PROMPT
      Analyze these security advisories and determine the optimal patch version:

      ## Input Data

      **Gem**: %{gem_name}
      **Current Version**: %{current_version}
      **Target Branch**: %{base_branch}
      **Advisory Count**: %{advisory_count}

      ## Security Advisories

      %{advisories_summary}

      ## Task

      1. Analyze the current version: %{current_version}
      2. Review each advisory's suggested fix version
      3. Determine the minimum version that fixes ALL advisories
      4. Check if this is a patch, minor, or major bump
      5. Assess confidence based on the decision rules

      Provide your analysis as valid JSON.
    PROMPT

    def initialize(client: Ai::DeepseekClient.new)
      @client = client
    end

    def enabled?
      @client.enabled?
    end

    def resolve(gem_name:, base_branch:, current_version:, bundled_advisories:)
      return fallback_resolution(current_version, bundled_advisories) unless enabled?

      advisories_summary = format_advisories(bundled_advisories)

      user_prompt = format(
        USER_PROMPT_TEMPLATE,
        base_branch: base_branch,
        gem_name: gem_name,
        current_version: current_version,
        advisory_count: bundled_advisories.size,
        advisories_summary: advisories_summary
      )

      result = @client.extract_json!(system: SYSTEM_PROMPT, user: user_prompt)
      recommendation = Recommendation.new(result)

      # Validate the recommendation makes sense
      validate_recommendation!(recommendation, current_version, bundled_advisories)

      recommendation
    rescue Ai::DeepseekClient::Error => e
      Rails.logger.error("[PatchVersionResolver] LLM error: #{e.message}")
      fallback_resolution(current_version, bundled_advisories)
    rescue ValidationError => e
      Rails.logger.warn("[PatchVersionResolver] LLM recommendation invalid: #{e.message}")
      fallback_resolution(current_version, bundled_advisories)
    end

    class ValidationError < StandardError; end

    private

    def format_advisories(bundled_advisories)
      bundled_advisories.map do |ba|
        advisory = ba.advisory
        cve_id = advisory.cve || advisory.fingerprint
        version = ba.suggested_fix_version || "(unknown)"
        severity = advisory.severity || "unknown"
        source = advisory.source

        "- **#{cve_id}** [#{severity.upcase}] (source: #{source})\n" \
        "  Suggested fix version: #{version}\n" \
        "  Affected: #{advisory.affected_requirement || 'unspecified'}"
      end.join("\n\n")
    end

    def validate_recommendation!(recommendation, current_version, bundled_advisories)
      return if recommendation.recommended_version.blank?

      begin
        recommended = Gem::Version.new(recommendation.recommended_version)
        current = Gem::Version.new(current_version)

        # Recommendation should not be lower than current version
        if recommended < current
          raise ValidationError, "Recommended version #{recommended} is lower than current #{current}"
        end

        # If there are suggested fix versions, recommendation should be >= highest required
        required_versions = bundled_advisories
          .reject { |ba| recommendation.excluded_advisories.include?(ba.advisory.cve) }
          .map(&:suggested_fix_version)
          .compact
          .map { |v| Gem::Version.new(v) rescue nil }
          .compact

        if required_versions.any? && recommended < required_versions.max
          raise ValidationError, "Recommended version #{recommended} doesn't satisfy highest required #{required_versions.max}"
        end
      rescue ArgumentError => e
        raise ValidationError, "Invalid version format: #{e.message}"
      end
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
          "reasoning" => "All advisories fixed by patch-level bump to #{highest} (fallback resolution)"
        })
      else
        Recommendation.new({
          "recommended_version" => parsed.max.to_s,
          "confidence" => "low",
          "reasoning" => "Mixed version requirements, needs manual review (fallback resolution)"
        })
      end
    end
  end
end
