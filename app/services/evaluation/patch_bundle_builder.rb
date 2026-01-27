module Evaluation
  class PatchBundleBuilder
    def initialize(
      version_resolver: RubyGems::VersionResolver.new,
      ruby_lang_resolver: RubyLang::SecurityAdvisoryResolver.new,
      ai_resolver: Ai::PatchVersionResolver.new,
      cap_enforcer: RateLimits::CapEnforcer.new
    )
      @version_resolver = version_resolver
      @ruby_lang_resolver = ruby_lang_resolver
      @ai_resolver = ai_resolver
      @cap_enforcer = cap_enforcer
    end

    # Called for each (branch_target, gem entry, advisory) tuple
    def build!(branch_target:, bundled_gems_content:, entry:, advisory:)
      # 1. Find or create PatchBundle for this branch + gem + current_version
      bundle = find_or_create_bundle(branch_target, entry)

      # 2. Determine suggested fix version for this specific advisory
      suggested_fix = determine_suggested_fix(entry, advisory)

      # 3. Link advisory to bundle
      link_advisory!(bundle, advisory, suggested_fix)

      # 4. Re-resolve target version across all linked advisories
      resolve_and_update!(bundle, branch_target, bundled_gems_content, entry)

      bundle
    rescue RubyGems::VersionResolver::ResolutionError,
           RubyCore::DiffValidator::ValidationError,
           Osv::Vulnerability::ParseError,
           Ghsa::Vulnerability::ParseError => e
      handle_resolution_error(branch_target, entry, advisory, e)
    end

    # For re-evaluation of awaiting_fix bundles
    def reevaluate!(bundle, bundled_gems_content: nil)
      branch_target = bundle.branch_target

      # Fetch fresh content if not provided
      bundled_gems_content ||= fetch_bundled_gems_content(branch_target)

      entry = build_entry(bundle.gem_name, bundle.current_version)

      # Re-check each advisory for updated fix versions
      bundle.bundled_advisories.each do |ba|
        new_fix = determine_suggested_fix(entry, ba.advisory)
        ba.update!(suggested_fix_version: new_fix) if new_fix != ba.suggested_fix_version
      end

      # Re-resolve
      resolve_and_update!(bundle, branch_target, bundled_gems_content, entry)
      bundle.update!(last_evaluated_at: Time.current)

      bundle
    end

    private

    def find_or_create_bundle(branch_target, entry)
      PatchBundle.find_or_create_by!(
        branch_target: branch_target,
        base_branch: branch_target.name,
        gem_name: entry.name,
        current_version: entry.version
      ) do |b|
        b.state = "pending"
      end
    end

    def link_advisory!(bundle, advisory, suggested_fix)
      ba = BundledAdvisory.find_or_initialize_by(
        patch_bundle: bundle,
        advisory: advisory
      )
      ba.suggested_fix_version = suggested_fix
      ba.save!
    end

    def determine_suggested_fix(entry, advisory)
      # Try to get fixed version from advisory data
      fixed = fixed_version_from_advisory(entry.version, advisory)

      # Cross-check with ruby-lang security page
      fixed = @ruby_lang_resolver.resolve_fixed_version(
        gem_name: entry.name,
        current_version: entry.version,
        cve: advisory.cve,
        fallback_fixed_version: fixed
      )

      fixed.presence
    end

    def fixed_version_from_advisory(entry_version, advisory)
      raw = advisory.raw
      case advisory.source
      when "ghsa"
        Ghsa::Vulnerability.pick_fixed_version(raw["firstPatchedVersion"], entry_version)
      else
        Osv::Vulnerability.pick_fixed_version(raw, entry_version)
      end
    rescue StandardError
      nil
    end

    def resolve_and_update!(bundle, branch_target, bundled_gems_content, entry)
      # Gather all suggested versions
      suggested_versions = bundle.bundled_advisories.reload.map(&:suggested_fix_version).compact

      if suggested_versions.empty?
        # No fix available for any advisory
        bundle.update!(
          state: "awaiting_fix",
          target_version: nil,
          blocked_reason: "no_fixed_version_available",
          last_evaluated_at: Time.current
        )
        return
      end

      # Try to resolve target version
      resolution = resolve_target_version(bundle, entry, suggested_versions)

      if resolution[:state] == :needs_review
        bundle.update!(
          state: "needs_review",
          target_version: resolution[:target],
          resolution_source: "llm",
          llm_recommendation: resolution[:llm_recommendation],
          blocked_reason: "conflicting_versions",
          last_evaluated_at: Time.current
        )
        return
      end

      # We have a target version - try to generate the diff
      target = resolution[:target]
      begin
        bumper = RubyCore::BundledGemsBumper.bump!(
          old_content: bundled_gems_content,
          gem_name: entry.name,
          target_version: target
        )

        # Check rate limits
        cap = @cap_enforcer.check!(
          gem_name: entry.name,
          base_branch: branch_target.name
        )

        state = cap.allowed ? "ready_for_review" : "blocked_rate_limited"

        bundle.update!(
          state: state,
          target_version: target,
          resolution_source: resolution[:source],
          llm_recommendation: resolution[:llm_recommendation] || {},
          proposed_diff: proposed_diff(bumper),
          blocked_reason: cap.allowed ? nil : cap.reason,
          next_eligible_at: cap.next_eligible_at,
          last_evaluated_at: Time.current
        )

        # Mark all advisories as included
        bundle.bundled_advisories.update_all(included_in_fix: true, exclusion_reason: nil)

        # Handle excluded advisories from LLM recommendation
        if resolution[:excluded_advisories].present?
          mark_excluded_advisories(bundle, resolution[:excluded_advisories], resolution[:exclusion_reason])
        end
      rescue RubyCore::BundledGemsFile::ParseError, RubyCore::DiffValidator::ValidationError => e
        bundle.update!(
          state: "awaiting_fix",
          target_version: target,
          blocked_reason: "bump_generation_failed: #{e.message}",
          last_evaluated_at: Time.current
        )
      end
    end

    def resolve_target_version(bundle, entry, suggested_versions)
      current = Gem::Version.new(entry.version)
      parsed = suggested_versions.map { |v| [v, Gem::Version.new(v)] rescue nil }.compact.to_h

      return { state: :awaiting_fix } if parsed.empty?

      # Check if all versions are patch-level compatible
      current_minor = "#{current.segments[0]}.#{current.segments[1]}"
      all_patch_level = parsed.values.all? do |v|
        "#{v.segments[0]}.#{v.segments[1]}" == current_minor
      end

      if all_patch_level
        # Simple case: all versions compatible, pick highest
        highest_version = parsed.max_by { |_, v| v }.first
        {
          state: :ready,
          target: highest_version,
          source: "auto",
          llm_recommendation: nil,
          excluded_advisories: [],
          exclusion_reason: nil
        }
      else
        # Complex case: use LLM to resolve
        llm_resolve(bundle, suggested_versions)
      end
    end

    def llm_resolve(bundle, suggested_versions)
      return manual_fallback(suggested_versions) unless @ai_resolver.enabled?

      recommendation = @ai_resolver.resolve(
        gem_name: bundle.gem_name,
        base_branch: bundle.base_branch,
        current_version: bundle.current_version,
        bundled_advisories: bundle.bundled_advisories.includes(:advisory)
      )

      if recommendation.confident?
        {
          state: :ready,
          target: recommendation.recommended_version,
          source: "llm",
          llm_recommendation: recommendation.to_h,
          excluded_advisories: recommendation.excluded_advisories,
          exclusion_reason: recommendation.exclusion_reason
        }
      else
        {
          state: :needs_review,
          target: recommendation.recommended_version,
          source: "llm",
          llm_recommendation: recommendation.to_h,
          excluded_advisories: recommendation.excluded_advisories,
          exclusion_reason: recommendation.exclusion_reason
        }
      end
    end

    def manual_fallback(suggested_versions)
      # Without LLM, flag for manual review with highest version as suggestion
      highest = suggested_versions.max_by { |v| Gem::Version.new(v) rescue Gem::Version.new("0") }
      {
        state: :needs_review,
        target: highest,
        source: "manual",
        llm_recommendation: { reasoning: "LLM not available, manual review required" },
        excluded_advisories: [],
        exclusion_reason: nil
      }
    end

    def mark_excluded_advisories(bundle, excluded_cves, reason)
      bundle.bundled_advisories.joins(:advisory).where(advisories: { cve: excluded_cves }).update_all(
        included_in_fix: false,
        exclusion_reason: reason
      )
    end

    def proposed_diff(bumper)
      <<~DIFF
        -#{bumper[:old_line].rstrip}
        +#{bumper[:new_line].rstrip}
      DIFF
    end

    def handle_resolution_error(branch_target, entry, advisory, error)
      bundle = find_or_create_bundle(branch_target, entry)

      link_advisory!(bundle, advisory, nil)

      # Only update state if not already in a better state
      unless %w[ready_for_review approved submitted].include?(bundle.state)
        bundle.update!(
          state: "awaiting_fix",
          blocked_reason: error.class.name,
          review_notes: error.message,
          last_evaluated_at: Time.current
        )
      end

      bundle
    end

    def fetch_bundled_gems_content(branch_target)
      fetcher = RubyCore::BundledGemsFetcher.new
      fetcher.fetch(repo: BotConfig.instance.upstream_repo, branch: branch_target.name)
    end

    def build_entry(gem_name, version)
      OpenStruct.new(name: gem_name, version: version)
    end
  end
end
