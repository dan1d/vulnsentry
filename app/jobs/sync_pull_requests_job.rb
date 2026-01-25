class SyncPullRequestsJob < ApplicationJob
  queue_as :default

  def perform(limit: 200)
    fetcher = Github::PullRequestStatusFetcher.new

    PullRequest.where.not(pr_number: nil).order(updated_at: :asc).limit(limit).find_each do |pr|
      sync_one(fetcher, pr)
    end
  end

  private
    def sync_one(fetcher, pr)
      data = fetcher.fetch(upstream_repo: pr.upstream_repo, pr_number: pr.pr_number)

      pr.update!(
        status: data.fetch(:status),
        opened_at: parse_time(data[:opened_at]) || pr.opened_at,
        merged_at: parse_time(data[:merged_at]),
        closed_at: parse_time(data[:closed_at]),
        last_synced_at: Time.current
      )
    end

    def parse_time(value)
      return nil if value.blank?
      Time.iso8601(value)
    rescue ArgumentError
      nil
    end
end
