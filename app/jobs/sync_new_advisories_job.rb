# frozen_string_literal: true

# Incremental advisory sync job that runs hourly to detect new vulnerabilities.
#
# Unlike the full EvaluateOsvVulnerabilitiesJob, this job:
# - Only checks gems that don't have recent advisory checks
# - Uses cached responses where available
# - Is lighter weight for more frequent runs
#
# This job is designed to catch new CVE disclosures quickly without
# overwhelming external APIs.
class SyncNewAdvisoriesJob < ApplicationJob
  queue_as :default

  # Time window for considering an advisory "recently checked"
  RECENT_CHECK_WINDOW = 4.hours

  def perform(force_refresh: false)
    branches = active_branches
    branch_details = []
    total_gems_checked = 0
    total_new_advisories = 0

    branches.find_each do |branch_target|
      result = sync_branch(branch_target, force_refresh: force_refresh)
      total_gems_checked += result[:gems_checked]
      total_new_advisories += result[:new_advisories]

      branch_details << {
        project: branch_target.project.slug,
        branch: branch_target.name,
        gems_checked: result[:gems_checked],
        new_advisories: result[:new_advisories]
      }
    end

    log_completion(
      branches: branch_details,
      gems_checked: total_gems_checked,
      new_advisories: total_new_advisories
    )
  end

  private

  # Batch size for processing large gem lists (Gemfile.lock projects)
  BATCH_SIZE = 25
  BATCH_DELAY_SECONDS = 0.5

  def active_branches
    # Process all enabled project types (bundled_gems and gemfile_lock)
    BranchTarget
      .joins(:project)
      .where(enabled: true)
      .where.not(maintenance_status: "eol")
      .where(projects: { enabled: true })
      .order("projects.slug ASC", "branch_targets.name ASC")
  end

  def sync_branch(branch_target, force_refresh:)
    project = branch_target.project
    fetcher = project.file_fetcher

    begin
      content = fetcher.fetch(branch: branch_target.name)
      file = project.parse_file(content)
    rescue ProjectFiles::Fetcher::FetchError => e
      log_fetch_error(branch_target, e)
      return { gems_checked: 0, new_advisories: 0 }
    end

    gems_to_check = select_gems_needing_check(file.entries, branch_target)

    # Use batch processing for large gem counts (Gemfile.lock projects)
    if gems_to_check.size > BATCH_SIZE
      evaluate_in_batches(branch_target, gems_to_check, content, force_refresh)
    else
      evaluate_sequentially(branch_target, gems_to_check, content, force_refresh)
    end
  end

  def evaluate_in_batches(branch_target, gems, content, force_refresh)
    result = { gems_checked: 0, new_advisories: 0 }

    gems.each_slice(BATCH_SIZE).with_index do |batch, idx|
      batch.each do |entry|
        check_result = check_gem_for_new_advisories(
          branch_target: branch_target,
          entry: entry,
          bundled_gems_content: content,
          force_refresh: force_refresh
        )
        result[:gems_checked] += 1
        result[:new_advisories] += check_result[:new_count]
      end

      # Small delay between batches to avoid rate limiting
      sleep(BATCH_DELAY_SECONDS) if idx > 0 && idx < (gems.size / BATCH_SIZE)
    end

    result
  end

  def evaluate_sequentially(branch_target, gems, content, force_refresh)
    result = { gems_checked: 0, new_advisories: 0 }

    gems.each do |entry|
      check_result = check_gem_for_new_advisories(
        branch_target: branch_target,
        entry: entry,
        bundled_gems_content: content,
        force_refresh: force_refresh
      )
      result[:gems_checked] += 1
      result[:new_advisories] += check_result[:new_count]
    end

    result
  end

  # Selects gems that haven't been checked recently.
  # This avoids re-checking gems that were just evaluated.
  def select_gems_needing_check(entries, branch_target)
    recently_checked_gems = Advisory
      .joins(:patch_bundles)
      .where(patch_bundles: { branch_target_id: branch_target.id })
      .where("advisories.updated_at > ?", RECENT_CHECK_WINDOW.ago)
      .distinct
      .pluck(:gem_name)

    entries.reject { |e| recently_checked_gems.include?(e.name) }
  end

  def check_gem_for_new_advisories(branch_target:, entry:, bundled_gems_content:, force_refresh:)
    advisory_chain = Evaluation::BundledGemsAdvisoryChain.new
    patch_bundle_builder = Evaluation::PatchBundleBuilder.new

    # Track advisories before check
    existing_fingerprints = Advisory.where(gem_name: entry.name).pluck(:fingerprint).to_set

    advisories = advisory_chain.ingest_for_version(
      gem_name: entry.name,
      version: entry.version,
      branch: branch_target.name
    )

    new_advisories = advisories.reject { |a| existing_fingerprints.include?(a.fingerprint) }

    # Build patch bundles for any new advisories
    new_advisories.each do |advisory|
      build_patch_bundle_safely(
        branch_target: branch_target,
        bundled_gems_content: bundled_gems_content,
        entry: entry,
        advisory: advisory,
        patch_bundle_builder: patch_bundle_builder
      )
    end

    { new_count: new_advisories.count }
  end

  def build_patch_bundle_safely(branch_target:, bundled_gems_content:, entry:, advisory:, patch_bundle_builder:)
    patch_bundle_builder.build!(
      branch_target: branch_target,
      bundled_gems_content: bundled_gems_content,
      entry: entry,
      advisory: advisory
    )
  rescue StandardError => e
    SystemEvent.create!(
      kind: "patch_bundle_build",
      status: "failed",
      message: e.message,
      payload: {
        branch: branch_target.name,
        gem_name: entry.name,
        advisory: advisory.fingerprint,
        class: e.class.name,
        job: self.class.name
      },
      occurred_at: Time.current
    )
  end

  def log_fetch_error(branch_target, error)
    SystemEvent.create!(
      kind: "bundled_gems_fetch",
      status: "failed",
      message: error.message,
      payload: {
        project: branch_target.project.slug,
        branch: branch_target.name,
        file_type: branch_target.project.file_type,
        job: self.class.name
      },
      occurred_at: Time.current
    )
  end

  def log_completion(branches:, gems_checked:, new_advisories:)
    # Group by project for summary
    by_project = branches.group_by { |b| b[:project] }
    project_summaries = by_project.transform_values do |project_branches|
      {
        branches: project_branches.map { |b| b[:branch] },
        gems_checked: project_branches.sum { |b| b[:gems_checked] },
        new_advisories: project_branches.sum { |b| b[:new_advisories] }
      }
    end

    SystemEvent.create!(
      kind: "sync_new_advisories",
      status: "ok",
      message: "Synced #{branches.count} branches across #{by_project.keys.count} projects, checked #{gems_checked} gems, found #{new_advisories} new advisories",
      payload: {
        total_branches: branches.count,
        total_projects: by_project.keys.count,
        total_gems_checked: gems_checked,
        total_new_advisories: new_advisories,
        by_project: project_summaries,
        branch_details: branches
      },
      occurred_at: Time.current
    )
  end
end
