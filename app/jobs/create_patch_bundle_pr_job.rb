# Creates a Pull Request for an approved PatchBundle.
# Similar to CreatePullRequestJob but works with the new PatchBundle model.
class CreatePatchBundlePrJob < ApplicationJob
  queue_as :default

  def perform(patch_bundle_id, draft: false)
    config = BotConfig.instance
    return if config.emergency_stop?

    bundle = PatchBundle.find(patch_bundle_id)

    bundle.with_lock do
      return unless bundle.state == "approved"
      return if bundle.pull_request.present?

      creator = Github::RubyCorePrCreator.new
      result = creator.create_for_patch_bundle!(bundle, draft: draft)

      PullRequest.transaction do
        PullRequest.create!(
          patch_bundle: bundle,
          upstream_repo: config.upstream_repo,
          fork_repo: config.fork_repo,
          head_branch: result[:head_branch],
          pr_number: result.fetch(:number),
          pr_url: result.fetch(:url),
          status: "open",
          opened_at: Time.current
        )

        bundle.update!(state: "submitted", created_pr_at: Time.current)
      end

      log_success(bundle, result)
    end
  rescue StandardError => e
    handle_failure(patch_bundle_id, e)
    raise
  end

  private

  def log_success(bundle, result)
    SystemEvent.create!(
      kind: "create_patch_bundle_pr",
      status: "ok",
      message: "Created PR ##{result[:number]} for #{bundle.gem_name} on #{bundle.base_branch}",
      payload: {
        patch_bundle_id: bundle.id,
        pr_number: result[:number],
        pr_url: result[:url],
        advisories_count: bundle.advisory_count,
        cves: bundle.cve_list
      },
      occurred_at: Time.current
    )
  end

  def handle_failure(patch_bundle_id, error)
    PatchBundle.where(id: patch_bundle_id).update_all(
      state: "failed",
      blocked_reason: error.class.name,
      review_notes: error.message,
      last_attempted_at: Time.current
    )

    exception_payload = { class: error.class.name, message: error.message, backtrace: error.backtrace }
    if error.is_a?(Github::GhCli::CommandError)
      exception_payload[:cmd] = error.cmd
      exception_payload[:stdout] = error.stdout
      exception_payload[:stderr] = error.stderr
      exception_payload[:exitstatus] = error.status&.exitstatus
    end

    SystemEvent.create!(
      kind: "create_patch_bundle_pr",
      status: "failed",
      message: error.message,
      payload: {
        patch_bundle_id: patch_bundle_id,
        exception: exception_payload
      },
      occurred_at: Time.current
    )
  end
end
