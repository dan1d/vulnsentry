class SyncPullRequestsJob < ApplicationJob
  queue_as :default

  def perform(limit: 200)
    status_fetcher = Github::PullRequestStatusFetcher.new
    comments_fetcher = Github::PullRequestCommentsFetcher.new

    PullRequest.where.not(pr_number: nil).order(updated_at: :asc).limit(limit).find_each do |pr|
      begin
        sync_one(status_fetcher, comments_fetcher, pr)
      rescue StandardError => e
        payload = { pr_id: pr.id, pr_number: pr.pr_number, upstream_repo: pr.upstream_repo, class: e.class.name }
        if e.is_a?(Github::GhCli::CommandError)
          payload[:cmd] = e.cmd
          payload[:stdout] = e.stdout
          payload[:stderr] = e.stderr
          payload[:exitstatus] = e.status&.exitstatus
        end

        SystemEvent.create!(
          kind: "sync_pull_requests",
          status: "warning",
          message: e.message,
          payload: payload,
          occurred_at: Time.current
        )
      end
    end
  end

  private
    def sync_one(status_fetcher, comments_fetcher, pr)
      status = status_fetcher.fetch(upstream_repo: pr.upstream_repo, pr_number: pr.pr_number)
      comments = comments_fetcher.fetch(upstream_repo: pr.upstream_repo, pr_number: pr.pr_number)

      pr.update!(
        status: status.fetch(:status),
        opened_at: parse_time(status[:opened_at]) || pr.opened_at,
        merged_at: parse_time(status[:merged_at]),
        closed_at: parse_time(status[:closed_at]),
        last_synced_at: Time.current,
        comments_snapshot: comments,
        comments_last_synced_at: Time.current
      )
    end

    def parse_time(value)
      return nil if value.blank?
      Time.iso8601(value)
    rescue ArgumentError
      nil
    end
end
