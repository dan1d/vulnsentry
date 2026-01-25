module Evaluation
  class CandidateBumpBuilder
    def initialize(
      version_resolver: RubyGems::VersionResolver.new,
      ruby_lang_resolver: RubyLang::SecurityAdvisoryResolver.new
    )
      @version_resolver = version_resolver
      @ruby_lang_resolver = ruby_lang_resolver
    end

    def build!(branch_target:, bundled_gems_content:, entry:, advisory:)
      fixed = fixed_version(entry_version: entry.version, advisory: advisory)
      fixed = @ruby_lang_resolver.resolve_fixed_version(
        gem_name: entry.name,
        current_version: entry.version,
        cve: advisory.cve,
        fallback_fixed_version: fixed
      )

      return block_no_fixed!(branch_target, entry, advisory) if fixed.blank?

      target = @version_resolver.resolve_target_version(
        gem_name: entry.name,
        affected_requirement: "< #{fixed}",
        current_version: entry.version,
        fixed_version: fixed,
        allow_major_minor: false
      )

      bumper = RubyCore::BundledGemsBumper.bump!(
        old_content: bundled_gems_content,
        gem_name: entry.name,
        target_version: target.to_s
      )

      cap = RateLimits::CapEnforcer.new.check!(
        gem_name: entry.name,
        base_branch: branch_target.name
      )

      upsert_candidate!(
        branch_target: branch_target,
        entry: entry,
        advisory: advisory,
        target_version: target.to_s,
        bumper: bumper,
        cap: cap
      )
    rescue RubyGems::VersionResolver::ResolutionError,
           RubyCore::DiffValidator::ValidationError,
           Osv::Vulnerability::ParseError,
           Ghsa::Vulnerability::ParseError => e
      block_ambiguous!(branch_target, entry, advisory, e)
    end

    private
      def fixed_version(entry_version:, advisory:)
        raw = advisory.raw
        return Ghsa::Vulnerability.pick_fixed_version(raw["firstPatchedVersion"], entry_version) if advisory.source == "ghsa"

        Osv::Vulnerability.pick_fixed_version(raw, entry_version)
      end

      def block_no_fixed!(branch_target, entry, advisory)
        CandidateBump.find_or_create_by!(
          advisory: advisory,
          branch_target: branch_target,
          base_branch: branch_target.name,
          gem_name: entry.name,
          current_version: entry.version,
          target_version: entry.version
        ) do |c|
          c.state = "blocked_ambiguous"
          c.blocked_reason = "#{advisory.source}_no_fixed_version"
        end
      end

      def upsert_candidate!(branch_target:, entry:, advisory:, target_version:, bumper:, cap:)
        state = cap.allowed ? "ready_for_review" : "blocked_rate_limited"

        CandidateBump.find_or_initialize_by(
          advisory: advisory,
          branch_target: branch_target,
          base_branch: branch_target.name,
          gem_name: entry.name,
          target_version: target_version
        ).tap do |c|
          c.current_version = entry.version
          c.state = state
          c.next_eligible_at = cap.next_eligible_at
          c.blocked_reason = cap.allowed ? nil : cap.reason
          c.proposed_diff = proposed_diff(bumper)
          c.review_notes = review_notes(advisory)
          c.save!
        end
      end

      def proposed_diff(bumper)
        <<~DIFF
          -#{bumper[:old_line].rstrip}
          +#{bumper[:new_line].rstrip}
        DIFF
      end

      def review_notes(advisory)
        [ advisory.cve, advisory.advisory_url, advisory.fingerprint ]
          .compact
          .join(" | ")
      end

      def block_ambiguous!(branch_target, entry, advisory, error)
        CandidateBump.find_or_create_by!(
          advisory: advisory,
          branch_target: branch_target,
          base_branch: branch_target.name,
          gem_name: entry.name,
          current_version: entry.version,
          target_version: entry.version
        ) do |c|
          c.state = "blocked_ambiguous"
          c.blocked_reason = error.class.name
          c.review_notes = error.message
        end
      end
  end
end
