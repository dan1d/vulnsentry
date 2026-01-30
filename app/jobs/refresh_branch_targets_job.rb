class RefreshBranchTargetsJob < ApplicationJob
  queue_as :default

  def perform
    fetcher = RubyLang::MaintenanceBranches.new
    html = fetcher.fetch_html
    all_branches = fetcher.parse_all_html(html)
    supported = all_branches.reject { |b| b.status == "eol" }

    cross_check_and_upsert!(html: html, supported: supported, all_branches: all_branches)
  end

  private
    def cross_check_and_upsert!(html:, supported:, all_branches:)
      cross = Ai::MaintenanceBranchesCrossCheck.new

      if cross.enabled?
        llm = cross.extract_branches!(html)
        # Compare all branches (including EOL) since LLM extracts everything
        cross.verify_match!(deterministic: all_branches, llm: llm)
      end

      ActiveRecord::Base.transaction do
        upsert_branches(all_branches)
        ensure_master!
      end

      # Once a branch is detected as EOL, we should not keep generating or surfacing
      # branch-specific bump candidates for it. Preserve auditability by rejecting
      # any non-submitted candidates/bundles tied to EOL branches.
      reject_eol_candidates!

      SystemEvent.create!(kind: "branch_refresh", status: "ok", message: "updated branch targets", payload: { count: supported.count }, occurred_at: Time.current)
    rescue Ai::DeepseekClient::Error, Ai::MaintenanceBranchesCrossCheck::MismatchError, RubyLang::MaintenanceBranches::ParseError => e
      # Best practice: warn_and_freeze (do not change branches).
      SystemEvent.create!(
        kind: "branch_refresh",
        status: "failed",
        message: e.message,
        payload: { class: e.class.name, url: RubyLang::MaintenanceBranches::URL },
        occurred_at: Time.current
      )
      raise
    end

    def reject_eol_candidates!
      now = Time.current
      eol_ids = BranchTarget.where(maintenance_status: "eol").pluck(:id)
      return if eol_ids.empty?

      CandidateBump
        .where(branch_target_id: eol_ids)
        .where.not(state: "submitted")
        .update_all(state: "rejected", blocked_reason: "branch is eol", updated_at: now)

      PatchBundle
        .where(branch_target_id: eol_ids)
        .where.not(state: "submitted")
        .update_all(state: "rejected", blocked_reason: "branch is eol", updated_at: now)
    end

    def upsert_branches(branches)
      source_url = RubyLang::MaintenanceBranches::URL
      now = Time.current

      seen_names = branches.map { |b| "ruby_#{b.series.tr('.', '_')}" }

      branches.each do |branch|
        name = "ruby_#{branch.series.tr('.', '_')}"
        row = BranchTarget.find_or_initialize_by(name: name)
        row.maintenance_status = branch.status
        row.source_url = source_url
        row.last_seen_at = now
        row.last_checked_at = now
        row.enabled = branch.status != "eol"
        row.save!
      end

      # Mark branches no longer on ruby-lang.org as EOL (excludes master).
      mark_unseen_as_eol!(seen_names, now)
    end

    def mark_unseen_as_eol!(seen_names, now)
      stale = BranchTarget
        .where.not(name: seen_names + [ "master" ])
        .where.not(maintenance_status: "eol")

      stale.find_each do |row|
        row.maintenance_status = "eol"
        row.enabled = false
        row.last_checked_at = now
        row.save!
      end
    end

    def ensure_master!
      now = Time.current
      row = BranchTarget.find_or_initialize_by(name: "master")
      row.maintenance_status ||= "normal"
      row.source_url ||= RubyLang::MaintenanceBranches::URL
      row.last_seen_at ||= now
      row.last_checked_at = now
      row.enabled = true if row.new_record? && row.enabled.nil?
      row.save!
    end
end
