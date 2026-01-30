class RefreshBranchTargetsJob < ApplicationJob
  queue_as :default

  # Refresh branch targets for all enabled projects or a specific project.
  # @param project_slug [String, nil] Optional slug to limit to a single project
  def perform(project_slug: nil)
    projects = if project_slug.present?
                 Project.enabled.where(slug: project_slug)
    else
                 Project.enabled
    end

    projects.find_each do |project|
      refresh_project(project)
    end
  end

  private

  def refresh_project(project)
    case project.branch_discovery
    when "ruby_lang"
      refresh_ruby_lang_branches(project)
    when "github_releases"
      # TODO: Implement GitHub releases-based branch discovery
      SystemEvent.create!(
        kind: "branch_refresh",
        status: "ok",
        message: "Skipped branch refresh for #{project.name} (github_releases not implemented)",
        payload: { project: project.slug, discovery_method: project.branch_discovery },
        occurred_at: Time.current
      )
    when "manual"
      # Manual projects don't auto-discover branches
      SystemEvent.create!(
        kind: "branch_refresh",
        status: "ok",
        message: "Skipped branch refresh for #{project.name} (manual discovery)",
        payload: { project: project.slug, discovery_method: project.branch_discovery },
        occurred_at: Time.current
      )
    else
      SystemEvent.create!(
        kind: "branch_refresh",
        status: "warning",
        message: "Unknown branch discovery method for #{project.name}",
        payload: { project: project.slug, discovery_method: project.branch_discovery },
        occurred_at: Time.current
      )
    end
  end

  def refresh_ruby_lang_branches(project)
    fetcher = RubyLang::MaintenanceBranches.new
    html = fetcher.fetch_html
    all_branches = fetcher.parse_all_html(html)
    supported = all_branches.reject { |b| b.status == "eol" }

    cross_check_and_upsert!(project: project, html: html, supported: supported, all_branches: all_branches)
  end

  def cross_check_and_upsert!(project:, html:, supported:, all_branches:)
    cross = Ai::MaintenanceBranchesCrossCheck.new

    if cross.enabled?
      llm = cross.extract_branches!(html)
      cross.verify_match!(deterministic: all_branches, llm: llm)
    end

    ActiveRecord::Base.transaction do
      upsert_branches(project, all_branches)
      ensure_master!(project)
    end

    reject_eol_candidates!(project)

    SystemEvent.create!(
      kind: "branch_refresh",
      status: "ok",
      message: "Updated branch targets for #{project.name}",
      payload: { project: project.slug, count: supported.count },
      occurred_at: Time.current
    )
  rescue Ai::DeepseekClient::Error, Ai::MaintenanceBranchesCrossCheck::MismatchError, RubyLang::MaintenanceBranches::ParseError => e
    SystemEvent.create!(
      kind: "branch_refresh",
      status: "failed",
      message: e.message,
      payload: { project: project.slug, class: e.class.name, url: RubyLang::MaintenanceBranches::URL },
      occurred_at: Time.current
    )
    raise
  end

  def reject_eol_candidates!(project)
    now = Time.current
    eol_ids = project.branch_targets.where(maintenance_status: "eol").pluck(:id)
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

  def upsert_branches(project, branches)
    source_url = RubyLang::MaintenanceBranches::URL
    now = Time.current

    seen_names = branches.map { |b| "ruby_#{b.series.tr('.', '_')}" }

    branches.each do |branch|
      name = "ruby_#{branch.series.tr('.', '_')}"
      row = project.branch_targets.find_or_initialize_by(name: name)
      row.maintenance_status = branch.status
      row.source_url = source_url
      row.last_seen_at = now
      row.last_checked_at = now
      row.enabled = branch.status != "eol"
      row.save!
    end

    mark_unseen_as_eol!(project, seen_names, now)
  end

  def mark_unseen_as_eol!(project, seen_names, now)
    stale = project.branch_targets
                   .where.not(name: seen_names + [ "master" ])
                   .where.not(maintenance_status: "eol")

    stale.find_each do |row|
      row.maintenance_status = "eol"
      row.enabled = false
      row.last_checked_at = now
      row.save!
    end
  end

  def ensure_master!(project)
    now = Time.current
    row = project.branch_targets.find_or_initialize_by(name: "master")
    row.maintenance_status ||= "normal"
    row.source_url ||= RubyLang::MaintenanceBranches::URL
    row.last_seen_at ||= now
    row.last_checked_at = now
    row.enabled = true if row.new_record? && row.enabled.nil?
    row.save!
  end
end
