class SyncPullRequestsJob < ApplicationJob
  queue_as :default

  # @param scope [String] "open", "closed", or nil (all)
  # @param limit [Integer] max PRs to sync per run
  def perform(scope: nil, limit: 200)
    status_fetcher = Github::PullRequestStatusFetcher.new
    comments_fetcher = Github::PullRequestCommentsFetcher.new

    prs = build_scope(scope, limit)

    prs.find_each do |pr|
      sync_one(status_fetcher, comments_fetcher, pr)
    rescue StandardError => e
      log_sync_error(pr, e)
    end
  end

  private
    def build_scope(scope, limit)
      base = PullRequest.where.not(pr_number: nil).order(updated_at: :asc)

      case scope
      when "open"
        base.where(status: "open")
      when "closed"
        base.where(status: %w[closed merged])
      else
        base
      end.limit(limit)
    end

    def sync_one(status_fetcher, comments_fetcher, pr)
      status = status_fetcher.fetch(upstream_repo: pr.upstream_repo, pr_number: pr.pr_number)
      new_comments = comments_fetcher.fetch(upstream_repo: pr.upstream_repo, pr_number: pr.pr_number)

      # Convert to string keys for storage and consistent access
      new_comments_hash = stringify_comments(new_comments)

      old_snapshot = pr.comments_snapshot || {}
      detect_new_maintainer_comments(pr, old_snapshot, new_comments_hash)

      review_state = derive_review_state(new_comments_hash["reviews"])

      pr.update!(
        status: status.fetch(:status),
        opened_at: parse_time(status[:opened_at]) || pr.opened_at,
        merged_at: parse_time(status[:merged_at]),
        closed_at: parse_time(status[:closed_at]),
        body: status[:body],
        labels: status[:labels] || [],
        review_state: review_state,
        last_synced_at: Time.current,
        comments_snapshot: new_comments_hash,
        comments_last_synced_at: Time.current
      )
    end

    def stringify_comments(comments)
      {
        "issue_comments" => comments[:issue_comments] || [],
        "reviews" => comments[:reviews] || [],
        "review_comments" => comments[:review_comments] || []
      }
    end

    def detect_new_maintainer_comments(pr, old_snapshot, new_snapshot)
      old_ids = extract_comment_ids(old_snapshot)

      all_new_comments = [
        *Array(new_snapshot["issue_comments"]),
        *Array(new_snapshot["reviews"]),
        *Array(new_snapshot["review_comments"])
      ]

      new_comments = all_new_comments.reject { |c| old_ids.include?(c["id"]) }
      maintainer_comments = new_comments.reject { |c| c["user"] == "dan1d" }

      maintainer_comments.each do |comment|
        SystemEvent.create!(
          kind: "maintainer_feedback",
          status: "info",
          message: "#{comment['user']} commented on PR ##{pr.pr_number}",
          payload: {
            pr_id: pr.id,
            pr_number: pr.pr_number,
            user: comment["user"],
            body: comment["body"]&.truncate(500),
            review_state: comment["state"]
          },
          occurred_at: Time.current
        )
      end
    end

    def extract_comment_ids(snapshot)
      return Set.new if snapshot.blank?

      ids = []
      ids.concat(Array(snapshot["issue_comments"]).map { |c| c["id"] })
      ids.concat(Array(snapshot["reviews"]).map { |c| c["id"] })
      ids.concat(Array(snapshot["review_comments"]).map { |c| c["id"] })
      ids.to_set
    end

    def derive_review_state(reviews)
      return "pending" if reviews.blank?

      # Get the most recent review from each user
      latest_by_user = {}
      Array(reviews).each do |r|
        user = r["user"]
        next if user.blank?
        latest_by_user[user] = r
      end

      return "pending" if latest_by_user.empty?

      states = latest_by_user.values.map { |r| r["state"] }

      # If any reviewer requested changes, that takes precedence
      return "changes_requested" if states.include?("CHANGES_REQUESTED")

      # If all reviewers approved
      return "approved" if states.all? { |s| s == "APPROVED" }

      # Otherwise pending (COMMENTED, PENDING, etc.)
      "pending"
    end

    def log_sync_error(pr, error)
      payload = {
        pr_id: pr.id,
        pr_number: pr.pr_number,
        upstream_repo: pr.upstream_repo,
        class: error.class.name
      }

      if error.is_a?(Github::GhCli::CommandError)
        payload[:cmd] = error.cmd
        payload[:stdout] = error.stdout
        payload[:stderr] = error.stderr
        payload[:exitstatus] = error.status&.exitstatus
      end

      SystemEvent.create!(
        kind: "sync_pull_requests",
        status: "warning",
        message: error.message,
        payload: payload,
        occurred_at: Time.current
      )
    end

    def parse_time(value)
      return nil if value.blank?
      Time.iso8601(value)
    rescue ArgumentError
      nil
    end
end
