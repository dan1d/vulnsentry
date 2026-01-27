class MigrateCandidateBumpsToPatchBundles < ActiveRecord::Migration[8.1]
  def up
    # Skip if no candidate_bumps exist
    return unless table_exists?(:candidate_bumps) && CandidateBump.any?

    # Group CandidateBumps by [branch_target_id, gem_name, current_version]
    # Each group becomes one PatchBundle
    groups = CandidateBump
      .select(:branch_target_id, :gem_name, :current_version)
      .distinct

    groups.each do |group|
      bumps = CandidateBump.where(
        branch_target_id: group.branch_target_id,
        gem_name: group.gem_name,
        current_version: group.current_version
      ).includes(:advisory, :pull_request)

      migrate_group(bumps)
    end
  end

  def down
    # This migration is not reversible - data has been consolidated
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def migrate_group(bumps)
    # Find the "best" bump to use as primary (submitted > approved > ready > blocked)
    primary = bumps.sort_by do |b|
      case b.state
      when "submitted" then 0
      when "approved" then 1
      when "ready_for_review" then 2
      when "blocked_rate_limited" then 3
      else 4
      end
    end.first

    # Map old state to new state
    new_state = map_state(primary.state, primary.target_version, primary.current_version)

    # Create PatchBundle
    bundle = PatchBundle.create!(
      branch_target_id: primary.branch_target_id,
      base_branch: primary.base_branch,
      gem_name: primary.gem_name,
      current_version: primary.current_version,
      target_version: has_real_fix?(primary) ? primary.target_version : nil,
      state: new_state,
      proposed_diff: primary.proposed_diff,
      blocked_reason: primary.blocked_reason,
      review_notes: primary.review_notes,
      resolution_source: "auto",
      next_eligible_at: primary.next_eligible_at,
      approved_at: primary.approved_at,
      approved_by: primary.approved_by,
      created_pr_at: primary.created_pr_at,
      last_attempted_at: primary.last_attempted_at,
      last_evaluated_at: Time.current
    )

    # Link all advisories from all bumps in the group
    bumps.each do |bump|
      BundledAdvisory.create!(
        patch_bundle: bundle,
        advisory: bump.advisory,
        suggested_fix_version: has_real_fix?(bump) ? bump.target_version : nil,
        included_in_fix: true
      )
    end

    # Migrate any existing pull_request
    if primary.pull_request.present?
      primary.pull_request.update!(patch_bundle_id: bundle.id)
    end
  end

  def map_state(old_state, target_version, current_version)
    # Handle the case where target == current (no real fix)
    no_fix = target_version == current_version

    case old_state
    when "pending"
      no_fix ? "awaiting_fix" : "pending"
    when "blocked_ambiguous"
      no_fix ? "awaiting_fix" : "needs_review"
    when "blocked_rate_limited"
      "blocked_rate_limited"
    when "ready_for_review"
      "ready_for_review"
    when "approved"
      "approved"
    when "rejected"
      "rejected"
    when "submitted"
      "submitted"
    when "failed"
      "failed"
    else
      no_fix ? "awaiting_fix" : "pending"
    end
  end

  def has_real_fix?(bump)
    bump.target_version.present? && bump.target_version != bump.current_version
  end
end
