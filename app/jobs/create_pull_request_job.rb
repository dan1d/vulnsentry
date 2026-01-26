class CreatePullRequestJob < ApplicationJob
  queue_as :default

  def perform(candidate_bump_id, draft: false)
    config = BotConfig.instance
    return if config.emergency_stop?

    candidate = CandidateBump.find(candidate_bump_id)

    candidate.with_lock do
      return unless candidate.state == "approved"
      return if candidate.pull_request.present?

      creator = Github::RubyCorePrCreator.new
      result = creator.create_for_candidate!(candidate, draft: draft)

      PullRequest.transaction do
        PullRequest.create!(
          candidate_bump: candidate,
          upstream_repo: config.upstream_repo,
          fork_repo: config.fork_repo,
          head_branch: result[:head_branch],
          pr_number: result.fetch(:number),
          pr_url: result.fetch(:url),
          status: "open",
          opened_at: Time.current
        )

        candidate.update!(state: "submitted", created_pr_at: Time.current)
      end
    end
  rescue StandardError => e
    CandidateBump.where(id: candidate_bump_id).update_all(
      state: "failed",
      blocked_reason: e.class.name,
      review_notes: e.message,
      last_attempted_at: Time.current
    )

    exception_payload = { class: e.class.name, message: e.message, backtrace: e.backtrace }
    if e.is_a?(Github::GhCli::CommandError)
      exception_payload[:cmd] = e.cmd
      exception_payload[:stdout] = e.stdout
      exception_payload[:stderr] = e.stderr
      exception_payload[:exitstatus] = e.status&.exitstatus
    end

    SystemEvent.create!(
      kind: "create_pr",
      status: "failed",
      message: e.message,
      payload: {
        candidate_bump_id: candidate_bump_id,
        exception: exception_payload
      },
      occurred_at: Time.current
    )
    raise
  end
end
