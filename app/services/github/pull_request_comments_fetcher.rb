module Github
  class PullRequestCommentsFetcher
    def initialize(gh: GhCli.new)
      @gh = gh
    end

    # Persists a "snapshot" shape that is stable for our app:
    # - issue_comments: regular PR conversation comments (issues API)
    # - reviews: PR reviews (approve/request changes/comment)
    # - review_comments: inline code review comments
    def fetch(upstream_repo:, pr_number:)
      {
        issue_comments: issue_comments(upstream_repo, pr_number),
        reviews: reviews(upstream_repo, pr_number),
        review_comments: review_comments(upstream_repo, pr_number)
      }
    end

    private
      def issue_comments(upstream_repo, pr_number)
        data = @gh.json!(
          "api",
          "--silent",
          "--paginate",
          "--slurp",
          "/repos/#{upstream_repo}/issues/#{pr_number}/comments"
        )

        Array(data).map do |c|
          {
            "id" => c["id"],
            "user" => c.dig("user", "login"),
            "created_at" => c["created_at"],
            "updated_at" => c["updated_at"],
            "body" => c["body"],
            "url" => c["html_url"]
          }
        end
      end

      def reviews(upstream_repo, pr_number)
        data = @gh.json!(
          "api",
          "--silent",
          "--paginate",
          "--slurp",
          "/repos/#{upstream_repo}/pulls/#{pr_number}/reviews"
        )

        Array(data).map do |r|
          {
            "id" => r["id"],
            "user" => r.dig("user", "login"),
            "state" => r["state"],
            "submitted_at" => r["submitted_at"],
            "body" => r["body"],
            "url" => r["html_url"]
          }
        end
      end

      def review_comments(upstream_repo, pr_number)
        data = @gh.json!(
          "api",
          "--silent",
          "--paginate",
          "--slurp",
          "/repos/#{upstream_repo}/pulls/#{pr_number}/comments"
        )

        Array(data).map do |c|
          {
            "id" => c["id"],
            "user" => c.dig("user", "login"),
            "path" => c["path"],
            "line" => c["line"],
            "position" => c["position"],
            "created_at" => c["created_at"],
            "updated_at" => c["updated_at"],
            "body" => c["body"],
            "url" => c["html_url"]
          }
        end
      end
  end
end

