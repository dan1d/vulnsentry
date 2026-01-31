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
      refresh_github_branches(project)
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

  def refresh_github_branches(project)
    fetcher = Github::BranchesFetcher.new
    branches = fetcher.fetch_rails_stable_branches(repo: project.upstream_repo)

    upsert_github_branches(project, branches)

    SystemEvent.create!(
      kind: "branch_refresh",
      status: "ok",
      message: "Updated branch targets for #{project.name} from GitHub",
      payload: { project: project.slug, count: branches.count, branches: branches.map(&:name) },
      occurred_at: Time.current
    )
  rescue Github::BranchesFetcher::FetchError => e
    SystemEvent.create!(
      kind: "branch_refresh",
      status: "failed",
      message: e.message,
      payload: { project: project.slug, class: e.class.name },
      occurred_at: Time.current
    )
    raise
  end

  def upsert_github_branches(project, branches)
    now = Time.current
    source_url = "https://github.com/#{project.upstream_repo}/branches"
    seen_names = []

    ActiveRecord::Base.transaction do
      branches.each do |branch|
        seen_names << branch.name
        row = project.branch_targets.find_or_initialize_by(name: branch.name)

        # Determine maintenance status based on branch position
        # Main/master is always "normal", older stable branches are "security"
        row.maintenance_status = determine_maintenance_status(branch.name, branches)
        row.source_url = source_url
        row.last_seen_at = now
        row.last_checked_at = now
        row.enabled = true if row.new_record?
        row.save!
      end

      # Mark branches not seen as EOL
      mark_unseen_github_branches_as_eol!(project, seen_names, now)
    end

    reject_eol_candidates!(project)
  end

  def determine_maintenance_status(branch_name, all_branches)
    # Main/master branch is always normal
    return "normal" if branch_name == "main" || branch_name == "master"

    # Get all stable branches sorted by version (newest first)
    stable_branches = all_branches
                        .select { |b| b.name.match?(/^\d+-\d+-stable$/) }
                        .sort_by { |b| version_to_array(b.name) }
                        .reverse

    return "normal" if stable_branches.empty?

    # Find position of this branch
    position = stable_branches.find_index { |b| b.name == branch_name }
    return "normal" unless position

    # Newest 2 stable branches are "normal", rest are "security"
    # Example: 7-2-stable, 7-1-stable = normal; 7-0-stable, 6-1-stable = security
    position < 2 ? "normal" : "security"
  end

  def version_to_array(branch_name)
    match = branch_name.match(/^(\d+)-(\d+)-stable$/)
    return [ 0, 0 ] unless match

    [ match[1].to_i, match[2].to_i ]
  end

  def mark_unseen_github_branches_as_eol!(project, seen_names, now)
    stale = project.branch_targets
                   .where.not(name: seen_names)
                   .where.not(maintenance_status: "eol")

    stale.find_each do |row|
      row.maintenance_status = "eol"
      row.enabled = false
      row.last_checked_at = now
      row.save!
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
