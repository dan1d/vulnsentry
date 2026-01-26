class CleanupForkBranchesJob < ApplicationJob
  queue_as :default

  def perform(limit: 200)
    return if BotConfig.instance.emergency_stop?

    cleaner = Github::ForkBranchCleaner.new
    pull_requests_to_clean(limit).find_each do |pr|
      cleanup_one(pr, cleaner)
    end
  end

  private
    def pull_requests_to_clean(limit)
      PullRequest
        .where(status: %w[merged closed], branch_deleted_at: nil)
        .where.not(head_branch: nil)
        .order(updated_at: :asc)
        .limit(limit)
    end

    def cleanup_one(pr, cleaner)
      return unless pr.head_branch.start_with?("bump-")

      deleted = cleaner.delete_branch(repo: pr.fork_repo, branch: pr.head_branch)
      pr.update!(branch_deleted_at: Time.current) if deleted
    rescue StandardError => e
      SystemEvent.create!(
        kind: "fork_branch_cleanup",
        status: "warning",
        message: e.message,
        payload: { pr_id: pr.id, fork_repo: pr.fork_repo, head_branch: pr.head_branch, class: e.class.name },
        occurred_at: Time.current
      )
    end
end
