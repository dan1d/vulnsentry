module Ai
  class AdvisoryAnalyzer
    class AnalysisResult
      attr_reader :prioritized_advisories, :summary, :high_priority_count,
                  :recommended_actions, :risk_assessment

      def initialize(data)
        @prioritized_advisories = data["prioritized_advisories"] || []
        @summary = data["summary"]
        @high_priority_count = data["high_priority_count"] || 0
        @recommended_actions = data["recommended_actions"] || []
        @risk_assessment = data["risk_assessment"]
      end

      def urgent?
        high_priority_count > 0
      end

      def to_h
        {
          prioritized_advisories: prioritized_advisories,
          summary: summary,
          high_priority_count: high_priority_count,
          recommended_actions: recommended_actions,
          risk_assessment: risk_assessment
        }
      end
    end

    class PrioritizedAdvisory
      attr_reader :cve, :gem_name, :priority_rank, :risk_score, :reasoning,
                  :severity, :exploitability, :impact_assessment

      def initialize(data)
        @cve = data["cve"]
        @gem_name = data["gem_name"]
        @priority_rank = data["priority_rank"]
        @risk_score = data["risk_score"] # 1-10 scale
        @reasoning = data["reasoning"]
        @severity = data["severity"]
        @exploitability = data["exploitability"]
        @impact_assessment = data["impact_assessment"]
      end

    def critical?
      return false if risk_score.nil?
      risk_score >= 8
    end

    def high?
      return false if risk_score.nil?
      risk_score >= 6
    end

      def to_h
        {
          cve: cve,
          gem_name: gem_name,
          priority_rank: priority_rank,
          risk_score: risk_score,
          reasoning: reasoning,
          severity: severity,
          exploitability: exploitability,
          impact_assessment: impact_assessment
        }
      end
    end

    SYSTEM_PROMPT = <<~PROMPT
      You are a security expert specializing in Ruby gem vulnerability assessment.
      Your task is to analyze security advisories and provide prioritized recommendations.

      ## Your Expertise

      - Deep knowledge of CVE severity scoring (CVSS)
      - Understanding of Ruby gem ecosystem and common usage patterns
      - Ability to assess real-world exploitability
      - Experience with security patch prioritization

      ## Risk Assessment Criteria

      Consider these factors when prioritizing advisories:

      1. **Severity Score** (from CVE/CVSS):
         - CRITICAL (9.0-10.0): Remote code execution, authentication bypass
         - HIGH (7.0-8.9): Significant data exposure, privilege escalation
         - MEDIUM (4.0-6.9): Limited impact vulnerabilities
         - LOW (0.1-3.9): Minor issues with mitigating factors

      2. **Gem Importance**:
         - Core gems (bundled with Ruby): Higher priority
         - Widely-used gems (rails, rack, etc.): Higher priority
         - Niche/optional gems: Lower relative priority

      3. **Exploitability**:
         - Remotely exploitable without authentication: CRITICAL
         - Requires local access or authentication: LOWER
         - Requires specific configurations: LOWER
         - Proof of concept available: HIGHER

      4. **Impact**:
         - Data confidentiality breach: HIGH
         - System integrity compromise: HIGH
         - Availability (DoS): MEDIUM
         - Limited scope/conditions: LOWER

      ## Output Requirements

      Respond with ONLY valid JSON (no markdown fences, no explanatory text).
      Every advisory must have a risk_score from 1-10 and clear reasoning.

      Required JSON schema:
      {
        "prioritized_advisories": [
          {
            "cve": "CVE-XXXX-YYYY",
            "gem_name": "gem_name",
            "priority_rank": 1,
            "risk_score": 8,
            "severity": "HIGH",
            "exploitability": "remote/local/requires_config",
            "impact_assessment": "Brief impact description",
            "reasoning": "Why this priority ranking"
          }
        ],
        "summary": "Overall assessment summary",
        "high_priority_count": 2,
        "risk_assessment": "Overall risk level and context",
        "recommended_actions": ["Action 1", "Action 2"]
      }
    PROMPT

    USER_PROMPT_TEMPLATE = <<~PROMPT
      Analyze and prioritize the following %{count} security advisories:

      ## Advisories to Analyze

      %{advisories_detail}

      ## Task

      1. Assess each advisory's severity and real-world exploitability
      2. Consider the importance of each affected gem in the Ruby ecosystem
      3. Rank advisories by priority (1 = highest priority)
      4. Assign risk scores (1-10) with clear reasoning
      5. Provide actionable recommendations

      Return your analysis as valid JSON.
    PROMPT

    def initialize(client: Ai::DeepseekClient.new)
      @client = client
    end

    def enabled?
      @client.enabled?
    end

    # Analyze a list of advisories and return prioritized results
    # @param advisories [Array<Advisory>] List of Advisory records
    # @return [AnalysisResult] Prioritized analysis with risk scores
    def analyze(advisories)
      return fallback_analysis(advisories) unless enabled?
      return empty_result if advisories.empty?

      user_prompt = format(
        USER_PROMPT_TEMPLATE,
        count: advisories.size,
        advisories_detail: format_advisories_for_analysis(advisories)
      )

      result = @client.extract_json!(system: SYSTEM_PROMPT, user: user_prompt)
      build_analysis_result(result, advisories)
    rescue Ai::DeepseekClient::Error => e
      Rails.logger.error("[AdvisoryAnalyzer] LLM error: #{e.message}")
      fallback_analysis(advisories)
    end

    # Analyze advisories grouped by gem for a holistic view
    # @param advisories [Array<Advisory>] List of Advisory records
    # @return [Hash] Analysis grouped by gem name
    def analyze_by_gem(advisories)
      return {} if advisories.empty?

      grouped = advisories.group_by(&:gem_name)
      results = {}

      grouped.each do |gem_name, gem_advisories|
        results[gem_name] = analyze(gem_advisories)
      end

      results
    end

    private

    def format_advisories_for_analysis(advisories)
      advisories.map.with_index(1) do |advisory, idx|
        severity = advisory.severity&.upcase || "UNKNOWN"
        cve = advisory.cve || advisory.fingerprint
        affected = advisory.affected_requirement || "unspecified versions"
        fixed = advisory.fixed_version || "unknown"
        url = advisory.advisory_url || "no URL"

        <<~ADVISORY
          ### Advisory #{idx}: #{cve}
          - **Gem**: #{advisory.gem_name}
          - **Severity**: #{severity}
          - **Source**: #{advisory.source}
          - **Affected Versions**: #{affected}
          - **Fixed Version**: #{fixed}
          - **Published**: #{advisory.published_at&.strftime('%Y-%m-%d') || 'unknown'}
          - **URL**: #{url}
          - **Raw Data Keys**: #{extract_raw_data_summary(advisory.raw)}
        ADVISORY
      end.join("\n")
    end

    def extract_raw_data_summary(raw)
      return "none" if raw.blank?

      # Extract useful fields from raw CVE data if available
      summary_parts = []

      if raw["severity"]
        summary_parts << "severity=#{raw['severity']}"
      end

      if raw["cvss"]
        summary_parts << "cvss=#{raw['cvss']}"
      end

      if raw["references"]&.any?
        summary_parts << "refs=#{raw['references'].size}"
      end

      summary_parts.empty? ? "standard" : summary_parts.join(", ")
    end

    def build_analysis_result(result, original_advisories)
      # Map prioritized advisories to our structured objects
      prioritized = (result["prioritized_advisories"] || []).map do |pa|
        PrioritizedAdvisory.new(pa)
      end

      # Sort by priority rank to ensure proper ordering
      prioritized.sort_by! { |pa| pa.priority_rank || 999 }

      # Convert back to string-keyed hashes for consistency
      prioritized_hashes = prioritized.map do |pa|
        pa.to_h.transform_keys(&:to_s)
      end

      AnalysisResult.new(
        "prioritized_advisories" => prioritized_hashes,
        "summary" => result["summary"],
        "high_priority_count" => result["high_priority_count"] || prioritized.count(&:high?),
        "recommended_actions" => result["recommended_actions"] || [],
        "risk_assessment" => result["risk_assessment"]
      )
    end

    def fallback_analysis(advisories)
      # Simple fallback: sort by severity
      severity_order = { "critical" => 0, "high" => 1, "medium" => 2, "low" => 3, nil => 4 }

      sorted = advisories.sort_by do |a|
        [ severity_order[a.severity&.downcase] || 4, a.published_at || Time.at(0) ]
      end

      prioritized = sorted.map.with_index(1) do |advisory, rank|
        risk_score = severity_to_risk_score(advisory.severity)

        {
          "cve" => advisory.cve || advisory.fingerprint,
          "gem_name" => advisory.gem_name,
          "priority_rank" => rank,
          "risk_score" => risk_score,
          "severity" => advisory.severity&.upcase || "UNKNOWN",
          "exploitability" => "unknown",
          "impact_assessment" => "Fallback analysis - review manually",
          "reasoning" => "Prioritized by severity level (fallback analysis)"
        }
      end

      high_count = prioritized.count { |p| (p["risk_score"] || 0) >= 6 }

      AnalysisResult.new(
        "prioritized_advisories" => prioritized,
        "summary" => "Fallback analysis based on severity scores. #{advisories.size} advisories analyzed.",
        "high_priority_count" => high_count,
        "recommended_actions" => [ "Review high-severity advisories first", "Verify fix versions are available" ],
        "risk_assessment" => "Automated fallback assessment - manual review recommended"
      )
    end

    def severity_to_risk_score(severity)
      case severity&.downcase
      when "critical" then 10
      when "high" then 8
      when "medium" then 5
      when "low" then 2
      else 4 # Unknown severity gets middle score
      end
    end

    def empty_result
      AnalysisResult.new(
        "prioritized_advisories" => [],
        "summary" => "No advisories to analyze",
        "high_priority_count" => 0,
        "recommended_actions" => [],
        "risk_assessment" => "No active vulnerabilities"
      )
    end
  end
end
